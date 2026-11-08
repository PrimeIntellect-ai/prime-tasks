#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_normalized_sensors_csv_exists_and_correct():
    csv_path = "/home/user/normalized_sensors.csv"

    # Check if the output file exists
    assert os.path.exists(csv_path), f"The output file {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"The path {csv_path} is not a file."

    # Expected rows based on the transformation rules
    expected_rows = [
        ["time", "device", "metric", "value"],
        ["2023-10-12T08:00:00Z", "alpha", "humidity", "45.1"],
        ["2023-10-12T08:00:00Z", "alpha", "temp", "22.5"],
        ["2023-10-12T08:00:00Z", "beta", "humidity", "44.0"],
        ["2023-10-12T08:00:00Z", "beta", "temp", "23.0"],
        ["2023-10-12T09:00:00Z", "alpha", "humidity", "46.2"],
        ["2023-10-12T09:00:00Z", "alpha", "temp", "22.8"],
        ["2023-10-12T09:00:00Z", "gamma", "humidity", "50.0"],
        ["2023-10-12T09:00:00Z", "gamma", "temp", "19.5"],
    ]

    # Read the actual CSV file
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if row]  # Ignore empty lines if any

    # Check the total number of rows
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in the CSV, "
        f"but found {len(actual_rows)}."
    )

    # Check each row exactly matches the expected output
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i+1} in {csv_path} does not match the expected content.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
