#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cleaned_measurements():
    file_path = "/home/user/data/cleaned_measurements.csv"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "timestamp,value",
        "2023-10-01T00:00:00Z,11.0",
        "2023-10-01T01:00:00Z,15.0",
        "2023-10-01T02:00:00Z,17.0",
        "2023-10-01T03:00:00Z,19.0",
        "2023-10-01T04:00:00Z,21.0"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but found {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {file_path}. Expected: '{expected}', Got: '{actual}'"

def test_generated_report():
    file_path = "/home/user/report.md"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read()

    assert "- Original Rows Processed: 6" in content, f"Missing or incorrect orig_rows in {file_path}"
    assert "- Cleaned Hourly Buckets: 5" in content, f"Missing or incorrect clean_rows in {file_path}"
    assert "- Peak Average Value: 21.0" in content, f"Missing or incorrect max_val in {file_path}"
    assert "- Lowest Average Value: 11.0" in content, f"Missing or incorrect min_val in {file_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
