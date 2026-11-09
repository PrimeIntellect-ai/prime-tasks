#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import csv
import pytest

INPUT_FILE = "/home/user/sensor_stream.log"
OUTPUT_FILE = "/home/user/clean_sensors.csv"

def is_valid_ip(ip_str):
    parts = ip_str.split('.')
    if len(parts) != 4:
        return False
    for part in parts:
        if not part.isdigit():
            return False
        if not (0 <= int(part) <= 255):
            return False
    return True

def compute_expected_csv():
    expected_rows = []
    expected_rows.append("timestamp,ip,temp,humidity,risk_level")

    if not os.path.exists(INPUT_FILE):
        return expected_rows

    with open(INPUT_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = [p.strip() for p in line.split('|')]
            if len(parts) < 4:
                continue

            timestamp = parts[0]
            ip_part = parts[2]
            msg_part = parts[3]

            if not ip_part.startswith("IP: "):
                continue
            ip_address = ip_part[4:].strip()

            if not is_valid_ip(ip_address):
                continue

            temp_match = re.search(r'\[temp=(-?\d+)\]', msg_part)
            hum_match = re.search(r'\[humidity=(-?\d+)\]', msg_part)

            if not temp_match or not hum_match:
                continue

            temp = int(temp_match.group(1))
            humidity = int(hum_match.group(1))

            if not (-50 <= temp <= 150):
                continue
            if not (0 <= humidity <= 100):
                continue

            risk_level = "HIGH" if (temp > 80 or humidity > 90) else "LOW"

            expected_rows.append(f"{timestamp},{ip_address},{temp},{humidity},{risk_level}")

    return expected_rows

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not created."

def test_output_file_content():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} is missing."

    expected_lines = compute_expected_csv()

    with open(OUTPUT_FILE, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) > 0, f"The output file {OUTPUT_FILE} is empty."

    assert actual_lines[0] == expected_lines[0], \
        f"Header mismatch. Expected '{expected_lines[0]}', got '{actual_lines[0]}'"

    assert len(actual_lines) == len(expected_lines), \
        f"Row count mismatch. Expected {len(expected_lines)} rows (including header), got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, \
            f"Row {i} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
