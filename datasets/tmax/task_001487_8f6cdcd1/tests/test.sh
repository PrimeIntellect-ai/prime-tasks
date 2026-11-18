#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import secrets
import subprocess
import pytest

RAW_FILE = "/home/user/raw_logs.jsonl"
OUTPUT_FILES = [
    "/home/user/clean_logs.jsonl",
    "/home/user/invalid_logs.jsonl",
    "/home/user/rolling_stats.csv",
    "/home/user/report.md",
]

# Replace the fixed fixture with an unpredictable equivalent fixture so the
# requested script must actually derive its outputs from raw_logs.jsonl.
base_ts = secrets.randbelow(900000) + 10000
times = [secrets.randbelow(90) + 1 for _ in range(7)]
token = secrets.token_hex(8)
bs = chr(92)
lines = [
    f'{{"ts": {base_ts}, "path": "/api/data", "time": {times[0]}, "msg": "ok {token}"}}',
    f'{{"ts": {base_ts + 1}, "path": "/api/data", "time": {times[1]}, "msg": "bad unicode {bs}u12G4"}}',
    f'{{"ts": {base_ts + 2}, "path": "/api/data", "time": {times[2]}, "msg": "ok"}}',
    f'{{"ts": {base_ts + 3}, "path": "/api/other", "time": {times[3]}, "msg": "ok"}}',
    f'{{"ts": {base_ts + 4}, "path": "/api/data", "time": {times[4]}, "msg": "ok"}}',
    f'{{"ts": {base_ts + 5}, "path": "/api/other", "time": {times[5]}, "msg": "short unicode {bs}u001"}}',
    f'{{"ts": {base_ts + 6}, "path": "/api/data", "time": {times[6]}, "msg": "valid unicode {bs}u1234"}}',
    f'{{"ts": {base_ts + 7}, "path": "/api/data/", "time": 9999, "msg": "path decoy"}}',
]
with open(RAW_FILE, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    script_path = "/home/user/process_logs.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    for path in OUTPUT_FILES:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

def test_script_exists_and_executable():
    script_path = "/home/user/process_logs.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def parse_and_split_logs(raw_file):
    with open(raw_file, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    clean_lines = []
    invalid_lines = []
    invalid_pattern = re.compile(re.escape(chr(92) + 'u') + r'(?![0-9a-fA-F]{4})')

    for line in lines:
        if invalid_pattern.search(line):
            invalid_lines.append(line)
        else:
            clean_lines.append(line)

    return clean_lines, invalid_lines

def test_log_filtering():
    raw_file = "/home/user/raw_logs.jsonl"
    clean_file = "/home/user/clean_logs.jsonl"
    invalid_file = "/home/user/invalid_logs.jsonl"

    assert os.path.exists(clean_file), f"{clean_file} does not exist."
    assert os.path.exists(invalid_file), f"{invalid_file} does not exist."

    expected_clean, expected_invalid = parse_and_split_logs(raw_file)

    with open(clean_file, 'r', encoding='utf-8') as f:
        actual_clean = f.read().splitlines()

    with open(invalid_file, 'r', encoding='utf-8') as f:
        actual_invalid = f.read().splitlines()

    assert actual_clean == expected_clean, f"Content of {clean_file} does not match expected."
    assert actual_invalid == expected_invalid, f"Content of {invalid_file} does not match expected."

def test_rolling_stats():
    raw_file = "/home/user/raw_logs.jsonl"
    stats_file = "/home/user/rolling_stats.csv"

    assert os.path.exists(stats_file), f"{stats_file} does not exist."

    expected_clean, _ = parse_and_split_logs(raw_file)

    api_data_entries = []
    for line in expected_clean:
        data = json.loads(line)
        if data.get("path") == "/api/data":
            api_data_entries.append(data)

    expected_csv_lines = ["ts,rolling_avg"]
    window = []
    for entry in api_data_entries:
        window.append(entry["time"])
        if len(window) > 3:
            window.pop(0)
        avg = sum(window) / len(window)
        expected_csv_lines.append(f'{entry["ts"]},{avg:.2f}')

    with open(stats_file, 'r', encoding='utf-8') as f:
        actual_csv_lines = f.read().splitlines()

    assert actual_csv_lines == expected_csv_lines, f"Content of {stats_file} does not match expected rolling average calculations."

def test_report_generation():
    raw_file = "/home/user/raw_logs.jsonl"
    report_file = "/home/user/report.md"

    assert os.path.exists(report_file), f"{report_file} does not exist."

    expected_clean, expected_invalid = parse_and_split_logs(raw_file)

    max_time = 0
    for line in expected_clean:
        data = json.loads(line)
        if data.get("path") == "/api/data":
            max_time = max(max_time, data.get("time", 0))

    expected_report = (
        "# Log Analysis Report\n\n"
        f"Total valid logs: {len(expected_clean)}\n"
        f"Total invalid logs: {len(expected_invalid)}\n"
        f"Max response time for /api/data: {max_time}\n"
    )

    with open(report_file, 'r', encoding='utf-8') as f:
        actual_report = f.read()

    assert actual_report.strip() == expected_report.strip(), f"Content of {report_file} does not match expected template and values."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
