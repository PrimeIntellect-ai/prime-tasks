#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import math

def test_clean_data_exists():
    path = "/home/user/clean_data.jsonl"
    assert os.path.exists(path), f"Output file {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

def test_clean_data_content():
    raw_path = "/home/user/raw_sensor_logs.txt"
    out_path = "/home/user/clean_data.jsonl"

    assert os.path.exists(raw_path), "Raw data file is missing."
    assert os.path.exists(out_path), "Output file is missing."

    valid_line_regex = re.compile(
        r'^\[(?P<year>\d{4})/(?P<month>\d{2})/(?P<day>\d{2})-(?P<hour>\d{2}):(?P<minute>\d{2}):(?P<second>\d{2})\]\s+\|\s+SENSOR_ID:\s+(?P<sensor_id>.+?)\s+\|\s+TEMP:\s+(?P<temp>-?\d+(?:\.\d+)?)F\s+\|\s+NOTES:\s+"(?P<notes>.*)"\s*$'
    )

    expected_data = []
    with open(raw_path, 'r', encoding='utf-8') as f:
        for line in f:
            match = valid_line_regex.match(line)
            if match:
                gd = match.groupdict()
                timestamp = f"{gd['year']}-{gd['month']}-{gd['day']}T{gd['hour']}:{gd['minute']}:{gd['second']}Z"
                temp_c = round((float(gd['temp']) - 32) * 5 / 9, 2)

                notes_raw = gd['notes'].lower()
                notes_clean = re.sub(r'[^a-z0-9\s]', '', notes_raw)
                tokens = [t for t in notes_clean.split() if t]

                expected_data.append({
                    "timestamp": timestamp,
                    "sensor_id": gd['sensor_id'],
                    "temp_celsius": temp_c,
                    "tokens": tokens
                })

    actual_data = []
    with open(out_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f"Line {line_num} in {out_path} is not valid JSON."

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} valid lines, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert "timestamp" in actual, f"Missing 'timestamp' in line {i+1}"
        assert "sensor_id" in actual, f"Missing 'sensor_id' in line {i+1}"
        assert "temp_celsius" in actual, f"Missing 'temp_celsius' in line {i+1}"
        assert "tokens" in actual, f"Missing 'tokens' in line {i+1}"

        assert actual["timestamp"] == expected["timestamp"], f"Timestamp mismatch at line {i+1}: expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual["sensor_id"] == expected["sensor_id"], f"Sensor ID mismatch at line {i+1}"
        assert math.isclose(actual["temp_celsius"], expected["temp_celsius"], rel_tol=1e-5), f"Temperature mismatch at line {i+1}: expected {expected['temp_celsius']}, got {actual['temp_celsius']}"
        assert actual["tokens"] == expected["tokens"], f"Tokens mismatch at line {i+1}: expected {expected['tokens']}, got {actual['tokens']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
