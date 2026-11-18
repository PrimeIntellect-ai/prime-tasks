#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

CSV_PATH = "/home/user/kickback_report.csv"

def test_kickback_report_exists():
    assert os.path.exists(CSV_PATH), f"Report file not found at {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file"

def test_kickback_report_content():
    expected_header = ["employee_a", "employee_b", "vendor_name", "account_name"]
    expected_rows = [
        ["Alice Smith", "Bob Jones", "Shady Corp", "Offshore Trust X"],
        ["Charlie Davis", "Alice Smith", "Shady Corp", "Main Bank Acct"]
    ]

    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

        rows = list(reader)
        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(rows)}"

        for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
            assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
