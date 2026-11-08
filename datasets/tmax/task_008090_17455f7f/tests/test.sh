#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_rolling_latency_csv():
    file_path = '/home/user/rolling_latency.csv'
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"Output path {file_path} is not a file."

    expected_rows = [
        ['timestamp', 'latency', 'rolling_avg'],
        ['2023-11-01T00:01:00Z', '50', '50.00'],
        ['2023-11-01T00:02:00Z', '100', '75.00'],
        ['2023-11-01T00:03:00Z', '150', '100.00'],
        ['2023-11-01T00:05:00Z', '200', '150.00'],
        ['2023-11-01T00:07:00Z', '10', '120.00']
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if row]

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
