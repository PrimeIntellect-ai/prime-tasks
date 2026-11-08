#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
from datetime import datetime, timedelta

SCRIPT_PATH = "/home/user/process_logs.sh"
RAW_PATH = "/home/user/raw_logs.txt"
CSV_PATH = "/home/user/processed_logs.csv"


def test_process_logs_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Script {script_path} is not executable."


def test_processed_logs_csv_content():
    csv_path = CSV_PATH
    assert os.path.exists(csv_path), f"Output file {csv_path} does not exist. Did you run your script?"
    assert os.path.isfile(csv_path), f"Path {csv_path} is not a file."

    expected_lines = [
        "timestamp,service,status,rolling_avg",
        "2023-10-01T10:00:01,auth,200,200",
        "2023-10-01T10:00:02,auth,500,350",
        "2023-10-01T10:00:03,auth,200,300",
        "2023-10-01T10:00:04,auth,503,401",
        "2023-10-01T10:00:05,db,200,200",
        "2023-10-01T10:00:06,db,404,302",
        "2023-10-01T10:00:08,db,200,268",
        "2023-10-01T10:00:09,db,200,268"
    ]

    with open(csv_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {csv_path}, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} in {csv_path} does not match expected output.\nExpected: {expected}\nActual: {actual.strip()}"


def test_script_processes_a_generated_mixed_format_fixture():
    suffix = secrets.token_hex(4)
    rng = secrets.SystemRandom()
    services = [f"zeta_{suffix}", f"alpha_{suffix}", f"middle_{suffix}"]
    offsets = [47, 3, 31, 12, 59]
    base = datetime(2025, 2, 3, 9, 10, 0)

    lines = []
    valid_records = []
    for service_index, service in enumerate(services):
        for request_index, offset in enumerate(offsets):
            timestamp = (base + timedelta(minutes=service_index * 7, seconds=offset)).strftime("%Y-%m-%dT%H:%M:%S")
            status = rng.randint(100, 599)
            valid_records.append((timestamp, service, status))
            if request_index % 2 == 0:
                # Use valid JSON with a field order different from the example.
                lines.append(json.dumps({"status": status, "service": service, "timestamp": timestamp}))
            else:
                lines.append(f"{timestamp},{service},{status}")

        invalid_time = (base + timedelta(minutes=service_index * 7, seconds=25)).strftime("%Y-%m-%dT%H:%M:%S")
        lines.extend([
            f"{invalid_time},{service},ERROR",
            f"{invalid_time},{service},20",
            f"{invalid_time},{service},1234",
            json.dumps({"timestamp": invalid_time, "service": service, "status": None}),
            json.dumps({"timestamp": invalid_time, "service": service, "status": "ERROR"}),
            json.dumps({"timestamp": invalid_time, "service": service, "status": 20}),
        ])

    rng.shuffle(lines)

    expected = ["timestamp,service,status,rolling_avg"]
    windows = {}
    for timestamp, service, status in sorted(valid_records, key=lambda record: (record[1], record[0])):
        window = windows.setdefault(service, [])
        window.append(status)
        if len(window) > 3:
            del window[0]
        expected.append(f"{timestamp},{service},{status},{sum(window) // len(window)}")

    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    original_output = None
    if os.path.isfile(CSV_PATH):
        with open(CSV_PATH, "rb") as f:
            original_output = f.read()

    try:
        with open(RAW_PATH, "w", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        if os.path.lexists(CSV_PATH):
            os.remove(CSV_PATH)

        proc = subprocess.run(
            ["/bin/bash", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert proc.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {proc.returncode}.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        assert os.path.isfile(CSV_PATH), f"Executing {SCRIPT_PATH} did not create {CSV_PATH}."

        with open(CSV_PATH, "r") as f:
            actual = f.read().strip().splitlines()
        actual = [line.rstrip("\r") for line in actual]
        assert actual == expected, (
            "Output from the generated mixed-format fixture was incorrect.\n"
            f"Expected:\n{chr(10).join(expected)}\nActual:\n{chr(10).join(actual)}"
        )
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if original_output is not None:
            with open(CSV_PATH, "wb") as f:
                f.write(original_output)
        elif os.path.lexists(CSV_PATH):
            os.remove(CSV_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
