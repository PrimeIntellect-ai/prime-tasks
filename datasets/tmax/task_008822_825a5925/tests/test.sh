#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_clean_metrics_exists():
    file_path = "/home/user/clean_metrics.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} should be a file."

def test_clean_metrics_content():
    file_path = "/home/user/clean_metrics.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"File {file_path} is empty."

    header = rows[0]
    expected_header = ["timestamp", "server", "role", "cpu", "cpu_rolling_avg"]
    assert header == expected_header, f"Header is incorrect. Expected {expected_header}, got {header}."

    expected_data = [
        ["1", "srv1", "web", "10.0", "10.0"],
        ["2", "srv1", "web", "20.0", "15.0"],
        ["3", "srv2", "db", "50.0", "50.0"],
        ["5", "srv1", "web", "30.0", "25.0"],
        ["6", "srv2", "db", "60.0", "55.0"]
    ]

    data_rows = rows[1:]

    # Strip any trailing empty lines
    while data_rows and not any(data_rows[-1]):
        data_rows.pop()

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but got {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert len(actual) == len(expected), f"Row {i+1} has incorrect number of columns."

        # Check string fields
        assert actual[0] == expected[0], f"Row {i+1} timestamp mismatch: expected {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1} server mismatch: expected {expected[1]}, got {actual[1]}"
        assert actual[2] == expected[2], f"Row {i+1} role mismatch: expected {expected[2]}, got {actual[2]}"

        # Check numeric fields with float conversion to handle formatting differences (e.g. 10 vs 10.0)
        try:
            actual_cpu = float(actual[3])
            expected_cpu = float(expected[3])
            assert abs(actual_cpu - expected_cpu) < 1e-6, f"Row {i+1} cpu mismatch: expected {expected_cpu}, got {actual_cpu}"
        except ValueError:
            pytest.fail(f"Row {i+1} cpu value '{actual[3]}' is not a valid float.")

        try:
            actual_avg = float(actual[4])
            expected_avg = float(expected[4])
            assert abs(actual_avg - expected_avg) < 1e-6, f"Row {i+1} cpu_rolling_avg mismatch: expected {expected_avg}, got {actual_avg}"
        except ValueError:
            pytest.fail(f"Row {i+1} cpu_rolling_avg value '{actual[4]}' is not a valid float.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
