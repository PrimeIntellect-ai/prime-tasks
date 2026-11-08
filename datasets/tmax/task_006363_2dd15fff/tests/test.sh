#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_merged_output_exists():
    csv_path = '/home/user/merged_output.csv'
    assert os.path.exists(csv_path), f"Output file {csv_path} is missing."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

def test_merged_output_contents():
    csv_path = '/home/user/merged_output.csv'

    if not os.path.exists(csv_path):
        pytest.fail(f"File {csv_path} not found.")

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The merged CSV file is empty."

    header = rows[0]
    expected_header = ['hour', 'temp', 'token_count']
    assert header == expected_header, f"Expected header {expected_header}, got {header}"

    data = rows[1:]

    expected_data = [
        ['2023-10-01 10:00:00', '20.0', '4'],
        ['2023-10-01 11:00:00', '22.0', '2'],
        ['2023-10-01 12:00:00', '24.0', '2'],
        ['2023-10-01 13:00:00', '26.0', '2'],
        ['2023-10-01 14:00:00', '25.5', '3']
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual[0] == expected[0], f"Row {i+1} hour mismatch: expected {expected[0]}, got {actual[0]}"

        # Check formatting of temp to exactly one decimal place
        assert '.' in actual[1] and len(actual[1].split('.')[1]) == 1, f"Row {i+1} temp '{actual[1]}' is not formatted to exactly one decimal place."
        assert float(actual[1]) == float(expected[1]), f"Row {i+1} temp mismatch: expected {expected[1]}, got {actual[1]}"

        assert actual[2] == expected[2], f"Row {i+1} token_count mismatch: expected {expected[2]}, got {actual[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
