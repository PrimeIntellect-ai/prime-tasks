#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

OUTPUT_FILE = "/home/user/output/merged_environment.csv"

def test_output_file_exists():
    """Check if the merged environment CSV file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing. Did you create it?"

def test_output_file_format_and_content():
    """Check the header, row count, and exact values of the output CSV."""
    if not os.path.exists(OUTPUT_FILE):
        pytest.fail(f"Output file {OUTPUT_FILE} does not exist.")

    with open(OUTPUT_FILE, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output file is empty."

    header = rows[0]
    expected_header = ["bucket_time", "avg_temperature", "avg_humidity"]
    assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 8, f"Expected exactly 8 data rows, got {len(data_rows)}."

    expected_data = [
        ["2023-10-01T10:00:00Z", "22.50", "45.50"],
        ["2023-10-01T10:15:00Z", "22.50", "45.50"],
        ["2023-10-01T10:30:00Z", "22.50", "42.00"],
        ["2023-10-01T10:45:00Z", "24.00", "40.00"],
        ["2023-10-01T11:00:00Z", "24.00", "40.00"],
        ["2023-10-01T11:15:00Z", "21.25", "38.00"],
        ["2023-10-01T11:30:00Z", "21.25", "38.00"],
        ["2023-10-01T11:45:00Z", "21.25", "38.00"],
    ]

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert len(actual) == 3, f"Row {i+1} does not have exactly 3 columns: {actual}"

        actual_time, actual_temp, actual_hum = actual
        expected_time, expected_temp, expected_hum = expected

        assert actual_time == expected_time, f"Row {i+1}: Expected bucket_time {expected_time}, got {actual_time}"

        # Check numeric values, allowing for minor formatting differences (e.g. 22.5 vs 22.50)
        # However, the spec requires EXACTLY 2 decimal places.
        assert actual_temp == expected_temp, f"Row {i+1}: Expected avg_temperature {expected_temp}, got {actual_temp}. Did you round to exactly 2 decimal places and forward-fill correctly?"
        assert actual_hum == expected_hum, f"Row {i+1}: Expected avg_humidity {expected_hum}, got {actual_hum}. Did you round to exactly 2 decimal places and forward-fill correctly?"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
