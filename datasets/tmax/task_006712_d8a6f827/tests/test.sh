#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import shutil
import signal
import string
import subprocess
import tempfile
import threading
from decimal import Decimal

import pytest

PROCESS_PATH = "/home/user/process.go"
DATA_DIR = "/home/user/data"
SUMMARY_PATH = "/home/user/summary.jsonl"
REQUIRED_KEYS = {"sensor_id", "window_start", "avg_temperature"}
TEMP_RE = re.compile(r'"avg_temperature"\s*:\s*(-?\d+\.\d{2})(?=\s*[,}])')

CANONICAL_FILES = {
    "sensor_1.csv": """timestamp,sensor_id,temperature,humidity
2023/10/01 10:01:15,S1,20.0,45.0
2023/10/01 10:03:00,S1,22.0,50.0
2023/10/01 10:04:59,S1,24.0,55.0
2023/10/01 10:05:00,S1,25.0,60.0
2023/10/01 10:06:30,S1,-100.0,60.0
2023/10/01 10:08:00,S1,26.0,150.0
2023/10/01 10:11:00,S1,28.0,60.0
""",
    "sensor_2.csv": """timestamp,sensor_id,temperature,humidity
2023/10/01 10:02:10,S2,15.5,80.0
2023/10/01 10:04:10,S2,16.5,82.0
2023/10/01 10:05:10,S2,17.0,101.0
2023/10/01 10:07:15,S2,18.0,85.0
2023/10/01 10:09:59,S2,19.0,88.0
""",
}


def clear_data_dir():
    os.makedirs(DATA_DIR, exist_ok=True)
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def install_files(files):
    clear_data_dir()
    for name, content in files.items():
        with open(os.path.join(DATA_DIR, name), "w", newline="") as f:
            f.write(content)


def run_program(executable, timeout=15):
    if os.path.lexists(SUMMARY_PATH):
        if os.path.isdir(SUMMARY_PATH) and not os.path.islink(SUMMARY_PATH):
            shutil.rmtree(SUMMARY_PATH)
        else:
            os.unlink(SUMMARY_PATH)
    result = subprocess.run(
        [executable], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f"process.go exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_and_validate_summary():
    # Preserve the original existence and JSONL assertions.
    assert os.path.isfile(SUMMARY_PATH), f"Output file {SUMMARY_PATH} is missing."
    with open(SUMMARY_PATH, "r") as f:
        raw = f.read()
    lines = raw.strip().split("\n")
    assert lines == sorted(lines), f"Lines in {SUMMARY_PATH} are not sorted alphabetically."

    parsed = []
    temp_strings = []
    for i, line in enumerate(lines):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {SUMMARY_PATH} is not valid JSON: {line}")
        assert isinstance(obj, dict), f"Line {i+1} is not a JSON object."
        assert set(obj.keys()) == REQUIRED_KEYS and len(obj) == 3, (
            f"Line {i+1} must contain exactly the keys {sorted(REQUIRED_KEYS)}."
        )
        assert isinstance(obj["sensor_id"], str), f"sensor_id on line {i+1} is not a string."
        assert isinstance(obj["window_start"], str), f"window_start on line {i+1} is not a string."
        assert isinstance(obj["avg_temperature"], (int, float)) and not isinstance(obj["avg_temperature"], bool), (
            f"avg_temperature on line {i+1} is not numeric."
        )
        match = TEMP_RE.search(line)
        assert match, f"avg_temperature on line {i+1} is not written with exactly two decimal places."
        parsed.append(obj)
        temp_strings.append(match.group(1))
    return lines, parsed, temp_strings


def assert_records(parsed, temp_strings, expected):
    actual = {}
    for obj, temp_string in zip(parsed, temp_strings):
        key = (obj["sensor_id"], obj["window_start"])
        assert key not in actual, f"Duplicate output record for {key}."
        actual[key] = (obj, temp_string)
    assert set(actual) == set(expected), (
        f"Output groups differ. Expected {sorted(expected)}, got {sorted(actual)}"
    )
    for key, expected_temp in expected.items():
        obj, temp_string = actual[key]
        assert abs(obj["avg_temperature"] - float(expected_temp)) < 1e-5, (
            f"Mismatch in avg_temperature for {key}: expected {expected_temp}, "
            f"got {obj['avg_temperature']}"
        )
        assert Decimal(temp_string) == Decimal(expected_temp), (
            f"Incorrect rounded value for {key}: expected {expected_temp}, got {temp_string}"
        )


def test_process_program():
    assert os.path.isfile(PROCESS_PATH), f"Required Go source file {PROCESS_PATH} is missing."
    assert not os.path.islink(PROCESS_PATH), f"{PROCESS_PATH} must be a regular source file, not a symlink."

    executable = os.path.join(tempfile.mkdtemp(prefix="verify-go-"), "process")
    build = subprocess.run(
        ["go", "build", "-o", executable, PROCESS_PATH],
        cwd="/home/user", text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"process.go does not build successfully:\n{build.stderr}"

    # Execute the submitted program on the original fixture, rather than trusting
    # an output file left behind by the agent.
    install_files(CANONICAL_FILES)
    run_program(executable)
    lines, parsed, temps = read_and_validate_summary()
    assert len(lines) == 5, f"Expected 5 lines in {SUMMARY_PATH}, found {len(lines)}."
    canonical_expected = {
        ("S1", "2023-10-01T10:00:00Z"): "22.00",
        ("S1", "2023-10-01T10:05:00Z"): "25.00",
        ("S1", "2023-10-01T10:10:00Z"): "28.00",
        ("S2", "2023-10-01T10:00:00Z"): "16.00",
        ("S2", "2023-10-01T10:05:00Z"): "18.50",
    }
    assert_records(parsed, temps, canonical_expected)

    # Use unpredictable data spread across multiple CSVs to verify that the
    # program really reads and aggregates the directory contents.
    token = ''.join(random.SystemRandom().choices(string.ascii_uppercase, k=8))
    day = random.SystemRandom().randint(10, 25)
    hour = random.SystemRandom().randint(11, 20)
    base = random.SystemRandom().randint(-20, 70)
    sensor_a = "A_" + token
    sensor_b = "B_" + token
    date_csv = f"2024/07/{day:02d}"
    date_iso = f"2024-07-{day:02d}"
    dynamic_files = {
        "part_alpha.csv": f"""timestamp,sensor_id,temperature,humidity
{date_csv} {hour:02d}:01:03,{sensor_a},{base}.11,40
{date_csv} {hour:02d}:06:00,{sensor_a},{base + 2}.40,50
bad timestamp,{sensor_a},77.00,50
{date_csv} {hour:02d}:02:00,{sensor_b},10.00,-1
{date_csv} {hour:02d}:03:00,{sensor_b},30.25,80
""",
        "part_beta.csv": f"""timestamp,sensor_id,temperature,humidity
{date_csv} {hour:02d}:04:59,{sensor_a},{base}.31,60
{date_csv} {hour:02d}:08:59,{sensor_a},{base + 2}.60,70
{date_csv} {hour:02d}:03:30,{sensor_b},31.75,90
{date_csv} {hour:02d}:07:00,{sensor_b},101.00,50
{date_csv} {hour:02d}:09:00,{sensor_b},-51.00,50
""",
    }
    install_files(dynamic_files)
    run_program(executable)
    _, parsed, temps = read_and_validate_summary()
    dynamic_expected = {
        (sensor_a, f"{date_iso}T{hour:02d}:00:00Z"): f"{base + Decimal('0.21'):.2f}",
        (sensor_a, f"{date_iso}T{hour:02d}:05:00Z"): f"{base + Decimal('2.50'):.2f}",
        (sensor_b, f"{date_iso}T{hour:02d}:00:00Z"): "31.00",
    }
    assert_records(parsed, temps, dynamic_expected)

    # Two FIFO-backed CSV files only release their contents after both have been
    # opened. Sequential file reading deadlocks, while concurrent readers finish.
    clear_data_dir()
    fifo_paths = [os.path.join(DATA_DIR, "concurrent_a.csv"), os.path.join(DATA_DIR, "concurrent_b.csv")]
    for path in fifo_paths:
        os.mkfifo(path, 0o666)

    fifo_sensor_a = "FIFO_A_" + token
    fifo_sensor_b = "FIFO_B_" + token
    payloads = [
        f"timestamp,sensor_id,temperature,humidity\n2025/08/09 12:01:00,{fifo_sensor_a},20.25,50\n",
        f"timestamp,sensor_id,temperature,humidity\n2025/08/09 12:02:00,{fifo_sensor_b},30.75,60\n",
    ]
    all_open = threading.Event()
    lock = threading.Lock()
    opened = [0]

    def fifo_writer(path, payload):
        try:
            fd = os.open(path, os.O_WRONLY)
            with lock:
                opened[0] += 1
                if opened[0] == 2:
                    all_open.set()
            if all_open.wait(60):
                os.write(fd, payload.encode())
            os.close(fd)
        except OSError:
            pass

    for path, payload in zip(fifo_paths, payloads):
        threading.Thread(target=fifo_writer, args=(path, payload), daemon=True).start()

    if os.path.lexists(SUMMARY_PATH):
        os.unlink(SUMMARY_PATH)
    proc = subprocess.Popen(
        [executable], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=12)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        pytest.fail("process.go did not read multiple CSV files concurrently.")
    assert proc.returncode == 0, f"Concurrent-input run failed:\nstdout:\n{stdout}\nstderr:\n{stderr}"
    _, parsed, temps = read_and_validate_summary()
    fifo_expected = {
        (fifo_sensor_a, "2025-08-09T12:00:00Z"): "20.25",
        (fifo_sensor_b, "2025-08-09T12:00:00Z"): "30.75",
    }
    assert_records(parsed, temps, fifo_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
