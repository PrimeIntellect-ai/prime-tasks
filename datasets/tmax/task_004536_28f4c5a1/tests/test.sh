#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

CSV_PATH = "/home/user/triangles.csv"

EXPECTED_ROWS = [
    ["A1", "A3", "A5", "6"],
    ["A1", "A2", "A3", "5"],
    ["A1", "A4", "A5", "5"],
    ["A2", "A3", "A5", "5"],
    ["A3", "A4", "A5", "5"],
    ["A1", "A2", "A5", "4"],
    ["A1", "A3", "A4", "4"],
    ["A2", "A3", "A4", "4"],
    ["A2", "A4", "A5", "4"],
    ["A1", "A2", "A4", "3"]
]

EXPECTED_HEADER = ["author1", "author2", "author3", "strength"]

def test_csv_file_exists():
    """Check if the triangles.csv file was created."""
    assert os.path.isfile(CSV_PATH), f"Failure: {CSV_PATH} not found."

def test_csv_header_and_content():
    """Check the CSV header and the exact rows in the correct order."""
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Failure: CSV file is empty."

    header = rows[0]
    assert header == EXPECTED_HEADER, f"Failure: Expected header {EXPECTED_HEADER}, but got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(EXPECTED_ROWS), f"Failure: Expected {len(EXPECTED_ROWS)} rows, but got {len(data_rows)}"

    for i, (actual_row, expected_row) in enumerate(zip(data_rows, EXPECTED_ROWS)):
        assert actual_row == expected_row, f"Failure: Row {i+1} mismatch. Expected {expected_row}, got {actual_row}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
