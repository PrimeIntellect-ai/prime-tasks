#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import threading
import time
from collections import defaultdict, deque

import pytest

SOURCE = "/home/user/processor.go"
INPUT = "/home/user/telemetry.csv"
OUTPUT = "/home/user/output.jsonl"
BINARY = "/tmp/telemetry_processor"

ORIGINAL_ROWS = [
    ("1", "D1", "20.0", "50.0"),
    ("2", "D1", "22.0", "51.0"),
    ("3", "D2", "19.0", "49.0"),
    ("4", "D1", "24.0", "50.0"),
    ("5", "D2", "21.0", "52.0"),
    ("6", "D1", "23.0", "50.0"),
    ("7", "D2", "20.0", "50.0"),
    ("8", "D2", "22.0", "51.0"),
]


def write_csv(rows):
    with open(INPUT, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "device_id", "temperature", "humidity"])
        writer.writerows(rows)


def process_group_rss_kib(pgid):
    total = 0
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            stat = open(f"/proc/{name}/stat", encoding="utf-8").read()
            fields = stat[stat.rfind(")") + 2:].split()
            if int(fields[2]) != pgid:
                continue
            with open(f"/proc/{name}/status", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
                        break
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
            pass
    return total


def run_processor(memory_limit_kib=None, timeout=30):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    proc = subprocess.Popen(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True
    )
    peak = 0
    stop = False

    def monitor():
        nonlocal peak
        while not stop:
            peak = max(peak, process_group_rss_kib(proc.pid))
            time.sleep(0.01)

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, 9)
        stdout, stderr = proc.communicate()
        pytest.fail(f"processor timed out after {timeout}s; stderr: {stderr[-2000:]}")
    finally:
        stop = True
        thread.join(timeout=1)
    peak = max(peak, process_group_rss_kib(proc.pid))
    assert proc.returncode == 0, f"processor exited with {proc.returncode}; stderr: {stderr[-4000:]}"
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."
    if memory_limit_kib is not None:
        assert peak <= memory_limit_kib, (
            f"processor used approximately {peak / 1024:.1f} MiB RSS on a large CSV; "
            f"the file must be processed row by row rather than retained in memory"
        )


def expected_records(rows):
    windows = defaultdict(lambda: deque(maxlen=3))
    counts = defaultdict(int)
    result = []
    for timestamp, device_id, temperature, humidity in rows:
        temp = float(temperature)
        hum = float(humidity)
        windows[device_id].append(temp)
        counts[device_id] += 1
        if counts[device_id] % 2 == 0:
            result.append({
                "device_id": device_id,
                "timestamp": timestamp,
                "temp_avg": f"{sum(windows[device_id]) / len(windows[device_id]):.2f}",
                "distance": f"{math.hypot(temp - 20.0, hum - 50.0):.2f}",
            })
    return result


def read_records():
    records = []
    with open(OUTPUT, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {line_num} in {OUTPUT} is not valid JSON: {e}")
            assert isinstance(record, dict), f"Line {line_num} is not a JSON object"
            assert set(record) == {"device_id", "timestamp", "temp_avg", "distance"}, (
                f"Line {line_num} does not contain exactly the required keys: {record}"
            )
            assert all(isinstance(record[k], str) for k in record), (
                f"All values on line {line_num} must be strings"
            )
            assert re.fullmatch(r"-?\d+\.\d{2}", record["temp_avg"]), "temp_avg must have exactly 2 decimals"
            assert re.fullmatch(r"\d+\.\d{2}", record["distance"]), "distance must have exactly 2 decimals"
            records.append(record)
    return records


@pytest.fixture(scope="session", autouse=True)
def build_and_restore():
    assert os.path.isfile(SOURCE), f"Expected Go source file {SOURCE} does not exist."
    source = open(SOURCE, "r", encoding="utf-8").read()
    assert re.search(r"^\s*package\s+main\b", source, re.MULTILINE), "processor.go must be a Go main package"
    forbidden = [
        (r"\.ReadAll\s*\(", "CSV/input ReadAll"),
        (r"\bio\.ReadAll\s*\(", "io.ReadAll"),
        (r"\bioutil\.ReadAll\s*\(", "ioutil.ReadAll"),
        (r"\bos\.ReadFile\s*\(", "os.ReadFile"),
        (r"\bioutil\.ReadFile\s*\(", "ioutil.ReadFile"),
    ]
    for pattern, name in forbidden:
        assert not re.search(pattern, source), f"{name} loads the input wholesale; process CSV rows as a stream"
    built = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert built.returncode == 0, f"processor.go does not compile as Go:\n{built.stderr}"
    yield
    write_csv(ORIGINAL_ROWS)
    run_processor(timeout=30)


def test_output_jsonl_exists():
    """Test that the output.jsonl file was created by running processor.go."""
    write_csv(ORIGINAL_ROWS)
    run_processor()
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."


def test_output_jsonl_content():
    """Retain the original fixed-data assertions after regenerating the output."""
    write_csv(ORIGINAL_ROWS)
    run_processor()
    expected = [
        {"device_id": "D1", "timestamp": "2", "temp_avg": "21.00", "distance": "2.24"},
        {"device_id": "D2", "timestamp": "5", "temp_avg": "20.00", "distance": "2.24"},
        {"device_id": "D1", "timestamp": "6", "temp_avg": "23.00", "distance": "3.00"},
        {"device_id": "D2", "timestamp": "8", "temp_avg": "21.00", "distance": "2.24"},
    ]
    actual = read_records()
    assert len(actual) == len(expected), f"Expected {len(expected)} records, but found {len(actual)}."
    key = lambda r: (r.get("device_id", ""), int(r.get("timestamp", "0")))
    for i, (got, want) in enumerate(zip(sorted(actual, key=key), sorted(expected, key=key))):
        assert got == want, f"Record mismatch at sorted index {i}. Expected: {want}; Actual: {got}"


def test_processor_handles_unseen_data():
    rows = [
        ("a1", "alpha", "10.0", "40.0"),
        ("b1", "beta", "30.0", "50.0"),
        ("a2", "alpha", "14.0", "50.0"),
        ("a3", "alpha", "22.0", "53.0"),
        ("b2", "beta", "18.0", "46.0"),
        ("a4", "alpha", "26.0", "58.0"),
        ("b3", "beta", "21.0", "51.0"),
        ("b4", "beta", "24.0", "47.0"),
        ("a5", "alpha", "19.0", "49.0"),
        ("a6", "alpha", "20.0", "50.0"),
    ]
    write_csv(rows)
    run_processor()
    assert read_records() == expected_records(rows)


def test_large_csv_is_streamed():
    count = 500000
    with open(INPUT, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "device_id", "temperature", "humidity"])
        for i in range(count):
            writer.writerow((str(i), f"S{i % 4}", str(18.0 + (i % 9) * 0.5), str(47.0 + (i % 7))))
    run_processor(memory_limit_kib=80 * 1024, timeout=60)
    emitted = 0
    with open(OUTPUT, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                json.loads(line)
                emitted += 1
    assert emitted == count // 2, f"Expected {count // 2} sampled records, found {emitted}"
PYTEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
