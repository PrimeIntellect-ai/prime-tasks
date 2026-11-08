#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_processed_file_exists():
    """Check that the final processed_hourly.csv file exists."""
    file_path = "/home/user/processed_hourly.csv"
    assert os.path.isfile(file_path), f"Missing output file: {file_path}. Ensure you have saved the final dataset to the correct path."

def test_processed_file_content():
    """Check that the processed_hourly.csv file has the correct content, format, and interpolation."""
    file_path = "/home/user/processed_hourly.csv"
    assert os.path.isfile(file_path), f"Missing output file: {file_path}"

    expected_rows = [
        ['timestamp', 'temperature'],
        ['2023-01-01 00:00:00', '10.0'],
        ['2023-01-01 01:00:00', '12.0'],
        ['2023-01-01 02:00:00', '14.0'],
        ['2023-01-01 03:00:00', '16.0'],
        ['2023-01-01 04:00:00', '18.0'],
        ['2023-01-01 05:00:00', '20.0'],
        ['2023-01-01 06:00:00', '23.0']
    ]

    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}. "
        "Ensure gaps are filled and duplicates are aggregated correctly."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i} mismatch.\n"
            f"Expected: {expected}\n"
            f"Got:      {actual}\n"
            "Check that dates are formatted correctly, temperatures are rounded to 1 decimal place, "
            "and linear interpolation is applied to the gaps."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
