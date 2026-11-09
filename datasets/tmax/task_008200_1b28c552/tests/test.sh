#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
import secrets
import subprocess
import pytest
from collections import defaultdict

SCRIPT_PATH = "/home/user/process.sh"
INPUT_PATH = "/home/user/data/telemetry.jsonl"
OUTPUT_PATH = "/home/user/rolling_stats.csv"


def compute_expected_results(input_file):
    data = defaultdict(lambda: defaultdict(list))

    with open(input_file, "r") as f:
        for line in f:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            device = record.get("device")
            ts = record.get("ts")
            val = record.get("val")

            if not device or not ts or val is None:
                continue

            hour = ts[:14] + "00:00Z"
            data[device][hour].append(val)

    expected_rows = []
    for device in sorted(data.keys()):
        hours = sorted(data[device].keys())
        hourly_avgs = []
        for i, hour in enumerate(hours):
            avg = sum(data[device][hour]) / len(data[device][hour])
            hourly_avgs.append(avg)
            start_idx = max(0, i - 2)
            window = hourly_avgs[start_idx:i + 1]
            rolling_avg = sum(window) / len(window)
            expected_rows.append({
                "device": device,
                "hour": hour,
                "hourly_avg": f"{avg:.2f}",
                "rolling_3_avg": f"{rolling_avg:.2f}",
            })

    return expected_rows


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "process.sh did not create rolling_stats.csv"


def check_output(expected_data):
    actual_data = []
    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["device", "hour", "hourly_avg", "rolling_3_avg"], \
            f"CSV headers are incorrect. Expected ['device', 'hour', 'hourly_avg', 'rolling_3_avg'], got {reader.fieldnames}"
        for row in reader:
            assert None not in row, "CSV row contains more fields than the header"
            actual_data.append(row)

    assert len(actual_data) == len(expected_data), \
        f"Row count mismatch. Expected {len(expected_data)} rows, got {len(actual_data)} rows."

    decimal_pattern = re.compile(r"^-?\d+\.\d{2}$")
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual["device"] == expected["device"], \
            f"Row {i+1}: device mismatch. Expected {expected['device']}, got {actual['device']}"
        assert actual["hour"] == expected["hour"], \
            f"Row {i+1}: hour mismatch. Expected {expected['hour']}, got {actual['hour']}"

        assert decimal_pattern.fullmatch(actual["hourly_avg"]), \
            f"Row {i+1}: hourly_avg must have exactly two decimal places, got {actual['hourly_avg']}"
        assert decimal_pattern.fullmatch(actual["rolling_3_avg"]), \
            f"Row {i+1}: rolling_3_avg must have exactly two decimal places, got {actual['rolling_3_avg']}"

        actual_hourly = float(actual["hourly_avg"])
        expected_hourly = float(expected["hourly_avg"])
        assert abs(actual_hourly - expected_hourly) < 0.015, \
            f"Row {i+1}: hourly_avg mismatch. Expected {expected['hourly_avg']}, got {actual['hourly_avg']}"

        actual_rolling = float(actual["rolling_3_avg"])
        expected_rolling = float(expected["rolling_3_avg"])
        assert abs(actual_rolling - expected_rolling) < 0.015, \
            f"Row {i+1}: rolling_3_avg mismatch. Expected {expected['rolling_3_avg']}, got {actual['rolling_3_avg']}"

        assert actual["hourly_avg"] == expected["hourly_avg"], \
            f"Row {i+1}: hourly_avg formatting/value mismatch. Expected {expected['hourly_avg']}, got {actual['hourly_avg']}"
        assert actual["rolling_3_avg"] == expected["rolling_3_avg"], \
            f"Row {i+1}: rolling_3_avg formatting/value mismatch. Expected {expected['rolling_3_avg']}, got {actual['rolling_3_avg']}"


@pytest.fixture(scope="session")
def original_expected():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    expected = compute_expected_results(INPUT_PATH)

    try:
        run_script()
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)

    return expected


def test_script_exists_and_executable(original_expected):
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_output_csv_exists(original_expected):
    assert os.path.isfile(OUTPUT_PATH), f"The output CSV {OUTPUT_PATH} was not created."


def test_output_csv_content(original_expected):
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    check_output(original_expected)


def test_script_processes_fresh_telemetry(original_expected):
    token = secrets.token_hex(4).upper()
    dev_a = f"ALPHA_{token}"
    dev_b = f"ZETA_{token}"
    base = 20 + secrets.randbelow(30)

    records = [
        {"ts": "2024-07-03T06:59:58Z", "device": dev_b, "val": base + 9, "msg": "late input"},
        {"ts": "2024-07-03T01:40:00Z", "device": dev_a, "val": base + 2, "msg": "comma, and unicode snowman ☃"},
        {"ts": "2024-07-03T09:05:00Z", "device": dev_a, "val": base - 4, "msg": "gap before this hour"},
        {"ts": "2024-07-03T01:05:00Z", "device": dev_a, "val": base, "msg": "first"},
        {"ts": "2024-07-03T03:15:00Z", "device": dev_a, "val": base + 7, "msg": "second present hour"},
        {"ts": "2024-07-03T10:25:00Z", "device": dev_a, "val": base + 11, "msg": "fourth present hour"},
        {"ts": "2024-07-03T02:10:00Z", "device": dev_b, "val": base - 5, "msg": "other device"},
        {"ts": "2024-07-03T02:50:00Z", "device": dev_b, "val": base + 1, "msg": "same bucket"},
    ]

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    try:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=True) + "\n")
            f.write('{"ts":"2024-07-03T03:30:00Z","device":"' + dev_a +
                    '","val":99999,"msg":"broken \\uZZZZ"}\n')
            f.write("this is not JSON at all\n")

        expected = compute_expected_results(INPUT_PATH)
        run_script()
        check_output(expected)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
