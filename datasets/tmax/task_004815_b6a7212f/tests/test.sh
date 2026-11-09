#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_processed_metrics_csv_exists():
    file_path = "/home/user/processed_metrics.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. Did you save the output?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_processed_metrics_csv_content():
    file_path = "/home/user/processed_metrics.csv"
    assert os.path.exists(file_path), f"Cannot check content, {file_path} is missing."

    expected_lines = [
        "timestamp,cpu,memory,temperature",
        "2023-10-01 10:00:00,0.0,1024.0,45.2",
        "2023-10-01 10:05:00,61.0,1024.0,45.2",
        "2023-10-01 10:10:00,61.0,2048.0,47.5",
        "2023-10-01 10:15:00,40.5,2048.0,47.5",
        "2023-10-01 10:20:00,99.9,2048.0,47.5"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
