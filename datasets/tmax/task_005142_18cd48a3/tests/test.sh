#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_hourly_summary_exists():
    """Test that the output CSV file exists."""
    file_path = "/home/user/hourly_summary.csv"
    assert os.path.isfile(file_path), f"The expected output file {file_path} is missing."

def test_hourly_summary_contents():
    """Test that the output CSV file has the correct headers and aggregated data."""
    file_path = "/home/user/hourly_summary.csv"

    expected_rows = [
        ["timestamp", "avg_temp"],
        ["2023-10-01 10:00:00", "23.00"],
        ["2023-10-01 11:00:00", "23.00"],
        ["2023-10-01 12:00:00", "24.00"],
        ["2023-10-01 13:00:00", "25.30"]
    ]

    actual_rows = []
    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # skip empty lines if any
                actual_rows.append(row)

    assert len(actual_rows) > 0, f"The file {file_path} is empty."

    # Check header
    assert actual_rows[0] == expected_rows[0], (
        f"Expected header {expected_rows[0]}, but got {actual_rows[0]}"
    )

    # Check data rows
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)-1} data rows, but got {len(actual_rows)-1}."
    )

    for i in range(1, len(expected_rows)):
        expected_ts, expected_temp = expected_rows[i]
        actual_ts, actual_temp = actual_rows[i]

        assert actual_ts == expected_ts, (
            f"Row {i}: Expected timestamp '{expected_ts}', got '{actual_ts}'."
        )

        # Parse float to allow minor formatting differences like "23.0" vs "23.00"
        # However, the prompt specifically requires "exactly 2 decimal places"
        assert actual_temp == expected_temp, (
            f"Row {i}: Expected avg_temp '{expected_temp}' (exactly 2 decimal places), got '{actual_temp}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
