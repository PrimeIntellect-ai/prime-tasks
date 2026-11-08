#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_processed_logs_exists():
    file_path = "/home/user/processed_logs.csv"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist. It must be created."

def test_processed_logs_content():
    file_path = "/home/user/processed_logs.csv"

    expected_rows = [
        ["timestamp", "cpu", "masked_ip"],
        ["2023-10-01T10:00:00Z", "40.0", "10.0.X.X"],
        ["2023-10-01T10:05:00Z", "30.0", "192.168.X.X"],
        ["2023-10-01T10:10:00Z", "50.0", "10.0.X.X"],
        ["2023-10-01T10:15:00Z", "55.0", "10.0.X.X"],
        ["2023-10-01T10:20:00Z", "60.0", "192.168.X.X"],
        ["2023-10-01T10:25:00Z", "65.0", "10.0.X.X"],
        ["2023-10-01T10:30:00Z", "70.0", "192.168.X.X"]
    ]

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"The file {file_path} is empty."

    # Check headers
    assert actual_rows[0] == expected_rows[0], (
        f"Headers are incorrect. Expected {expected_rows[0]}, but got {actual_rows[0]}"
    )

    # Check number of rows
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows (including header), but found {len(actual_rows)}."
    )

    # Check contents row by row
    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], (
            f"Row {i+1} is incorrect.\n"
            f"Expected: {expected_rows[i]}\n"
            f"Actual:   {actual_rows[i]}\n"
            "Ensure sorting, IP masking, and CPU interpolation are correct."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
