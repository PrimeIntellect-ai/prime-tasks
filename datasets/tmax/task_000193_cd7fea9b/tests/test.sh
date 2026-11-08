#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from collections import defaultdict
import pytest

def test_output_file_exists():
    output_file = "/home/user/minute_avg_temp.csv"
    assert os.path.exists(output_file), f"Output file {output_file} is missing."
    assert os.path.isfile(output_file), f"{output_file} is not a regular file."

def test_output_content():
    input_file = "/home/user/raw_sensors.csv"
    assert os.path.exists(input_file), f"Input file {input_file} is missing, cannot compute expected output."

    expected_data = defaultdict(list)
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row['temperature'] or not row['humidity']:
                continue
            try:
                temp = float(row['temperature'])
                hum = float(row['humidity'])
            except ValueError:
                continue

            if not (-50.0 <= temp <= 150.0):
                continue
            if not (0.0 <= hum <= 100.0):
                continue

            ts = row['timestamp']
            if len(ts) >= 19 and ts.endswith('Z'):
                minute_ts = ts[:17] + "00Z"
                expected_data[minute_ts].append(temp)

    expected_rows = []
    for ts in sorted(expected_data.keys()):
        avg_temp = sum(expected_data[ts]) / len(expected_data[ts])
        expected_rows.append((ts, f"{avg_temp:.1f}"))

    output_file = "/home/user/minute_avg_temp.csv"
    actual_rows = []
    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["timestamp", "avg_temperature"], f"Incorrect header in {output_file}. Expected ['timestamp', 'avg_temperature'], got {header}."
        for row in reader:
            if row:  # skip empty lines if any
                actual_rows.append(tuple(row))

    assert actual_rows == expected_rows, f"Data mismatch in {output_file}. Expected {expected_rows}, got {actual_rows}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
