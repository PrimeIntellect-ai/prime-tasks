#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_output_file_exists():
    """Test that the output file loc_rolling_report.csv exists."""
    output_path = "/home/user/loc_rolling_report.csv"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

def test_output_file_encoding():
    """Test that the output file is encoded in UTF-8."""
    output_path = "/home/user/loc_rolling_report.csv"
    try:
        with open(output_path, 'rb') as f:
            raw_data = f.read()
            # Verify it decodes cleanly as utf-8
            raw_data.decode('utf-8')
    except UnicodeDecodeError:
        pytest.fail(f"File {output_path} is not valid UTF-8.")

def test_output_file_content():
    """Test that the output file has the correct headers and content."""
    output_path = "/home/user/loc_rolling_report.csv"

    expected_data = [
        ["2023-10-01", "5"],
        ["2023-10-02", "5"],
        ["2023-10-03", "7"],
        ["2023-10-04", "2"],
        ["2023-10-05", "2"],
        ["2023-10-06", "8"],
        ["2023-10-07", "9"],
    ]

    with open(output_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The output CSV file is empty."

    header = rows[0]
    assert header == ["date", "rolling_count"], f"Incorrect headers. Expected ['date', 'rolling_count'], got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
