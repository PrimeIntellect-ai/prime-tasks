#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_processed_errors_csv_exists():
    output_path = "/home/user/processed_errors.csv"
    assert os.path.isfile(output_path), f"Expected output file not found: {output_path}"

def test_processed_errors_csv_content():
    output_path = "/home/user/processed_errors.csv"
    assert os.path.isfile(output_path), f"Expected output file not found: {output_path}"

    with open(output_path, 'r', newline='') as f:
        reader = list(csv.reader(f))

    expected = [
        ['timestamp', 'masked_user', 'dept', 'error_code'],
        ['2023-10-24 10:15:00', '12**', 'Sales', 'ERR_OOM'],
        ['2023-10-24 10:16:30', '56**', 'Engineering', 'ERR_TIMEOUT'],
        ['2023-10-24 11:05:12', '12**', 'Sales', 'ERR_OOM'],
        ['2023-10-24 12:00:01', '90**', 'HR', 'ERR_ACCESS_DENIED']
    ]

    assert len(reader) > 0, "The processed_errors.csv file is empty."
    assert reader[0] == expected[0], f"Header mismatch. Expected {expected[0]}, got {reader[0]}"

    assert len(reader) == len(expected), f"Expected {len(expected)} rows (including header), got {len(reader)} rows."

    for i in range(1, len(expected)):
        assert reader[i] == expected[i], f"Row {i} mismatch. Expected {expected[i]}, got {reader[i]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
