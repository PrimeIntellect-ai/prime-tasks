#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_processed_samples_exists_and_content():
    path = "/home/user/processed_samples.csv"
    assert os.path.isfile(path), f"Output file {path} is missing."

    expected_rows = [
        ['interaction_id', 'category', 'has_email'],
        ['C001', 'billing', 'True'],
        ['C002', 'billing', 'False'],
        ['C003', 'refund', 'True'],
        ['C007', 'refund', 'False'],
        ['C004', 'shipping', 'False'],
        ['C005', 'shipping', 'False']
    ]

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"{path} is empty."

    # Check headers
    assert actual_rows[0] == expected_rows[0], f"Header mismatch in {path}."

    # Check data rows
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch in {path}: expected {expected}, got {actual}"

def test_process_log_exists_and_content():
    path = "/home/user/process.log"
    assert os.path.isfile(path), f"Log file {path} is missing."

    expected_log = "Pipeline finished. Processed 10 rows. Saved 6 rows across 3 categories."

    with open(path, "r") as f:
        content = f.read()

    assert expected_log in content, f"Expected log message '{expected_log}' not found in {path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
