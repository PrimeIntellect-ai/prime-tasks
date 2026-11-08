#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

CSV_PATH = "/home/user/category_metrics.csv"

def test_csv_exists():
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} is missing."

def test_csv_content():
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} is missing."

    expected_content = [
        "Science,1050,1",
        "Physics,550,2",
        "Biology,500,3",
        "Quantum,450,4",
        "Genetics,300,5"
    ]

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_content), f"Expected {len(expected_content)} lines, found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_content, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
