#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_risk_scores_csv_exists():
    path = "/home/user/risk_scores.csv"
    assert os.path.exists(path), f"Output file does not exist: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"

def test_risk_scores_csv_contents():
    path = "/home/user/risk_scores.csv"
    assert os.path.exists(path), f"Output file does not exist: {path}"

    expected_rows = [
        ["patient_id", "risk_score"],
        ["1", "59.40"],
        ["2", "73.60"],
        ["3", "68.00"],
        ["4", "56.02"],
        ["5", "80.00"]
    ]

    actual_rows = []
    with open(path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            # Strip whitespace in case of minor formatting differences
            actual_rows.append([col.strip() for col in row])

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i + 1} mismatch: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
