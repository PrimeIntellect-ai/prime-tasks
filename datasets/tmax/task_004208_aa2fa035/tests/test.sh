#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_summary_csv_exists():
    summary_path = '/home/user/summary.csv'
    assert os.path.isfile(summary_path), f"Output file {summary_path} does not exist. The script did not run or failed to create the file."

def test_summary_csv_content():
    summary_path = '/home/user/summary.csv'

    expected_rows = [
        ['2023-10-01T10:00:00Z', 'cpu', '47.75', '1'],
        ['2023-10-01T10:00:00Z', 'disk', '55.0', '1'],
        ['2023-10-01T10:00:00Z', 'memory', '1036.0', '1'],
        ['2023-10-01T10:05:00Z', 'cpu', '47.75', '2'],
        ['2023-10-01T10:05:00Z', 'disk', '55.0', '2'],
        ['2023-10-01T10:05:00Z', 'memory', '1036.0', '2'],
        ['2023-10-01T10:10:00Z', 'cpu', '80.0', '1'],
        ['2023-10-01T10:10:00Z', 'disk', '120.0', '1'],
        ['2023-10-01T10:10:00Z', 'memory', '2048.0', '1'],
        ['2023-10-01T10:15:00Z', 'cpu', '40.0', '2'],
        ['2023-10-01T10:15:00Z', 'disk', '30.0', '2'],
        ['2023-10-01T10:15:00Z', 'memory', '512.0', '2']
    ]
    expected_header = ['timestamp', 'metric', 'mean_value', 'alert_count']

    with open(summary_path, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {summary_path} is empty.")

        assert header == expected_header, f"Header in {summary_path} is incorrect. Expected {expected_header}, got {header}."

        rows = list(reader)

        # Check row count
        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)} rows."

        # Check each row exactly
        for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
            assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
