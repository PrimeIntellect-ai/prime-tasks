#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import csv

def test_report_exists():
    file_path = "/home/user/report.tsv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_report_content():
    file_path = "/home/user/report.tsv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter='\t')
        rows = list(reader)

    assert len(rows) == 2, f"Expected exactly 2 rows in report.tsv, got {len(rows)}"

    expected_rows = [
        ["2021-10-01 12:00:00", "3.1", "1"],
        ["2021-10-01 13:00:00", "4.0", "2"]
    ]

    for i, expected in enumerate(expected_rows):
        assert rows[i] == expected, f"Row {i+1} mismatch: expected {expected}, got {rows[i]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
