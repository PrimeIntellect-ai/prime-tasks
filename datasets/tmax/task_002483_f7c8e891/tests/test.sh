#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

CSV_PATH = '/home/user/compliance_report.csv'

EXPECTED_ROWS = [
    ['EmployeeName', 'ZoneName', 'SwipeTime'],
    ['Charlie Brown', 'Server Room A', '2023-10-01 23:15:00'],
    ['Diana Prince', 'Server Room B', '2023-10-02 02:30:00'],
    ['Alice Smith', 'Server Room B', '2023-10-02 04:55:00']
]

def test_csv_exists():
    """Check if the compliance report CSV file was created."""
    assert os.path.isfile(CSV_PATH), f"Expected CSV file at {CSV_PATH} is missing."

def test_csv_content():
    """Check if the CSV content matches the expected output."""
    assert os.path.isfile(CSV_PATH), f"Cannot check content, file {CSV_PATH} is missing."

    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(EXPECTED_ROWS), (
        f"Expected {len(EXPECTED_ROWS)} rows (including header), but found {len(actual_rows)} rows."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, EXPECTED_ROWS)):
        assert actual == expected, (
            f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"
        )

def test_csv_raw_formatting():
    """Check if the CSV file follows the strict formatting requirements (no extra quotes unless required)."""
    assert os.path.isfile(CSV_PATH), f"Cannot check raw formatting, file {CSV_PATH} is missing."

    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip().replace('\r\n', '\n')

    expected_content = (
        "EmployeeName,ZoneName,SwipeTime\n"
        "Charlie Brown,Server Room A,2023-10-01 23:15:00\n"
        "Diana Prince,Server Room B,2023-10-02 02:30:00\n"
        "Alice Smith,Server Room B,2023-10-02 04:55:00"
    )

    assert content == expected_content, (
        "The raw content of the CSV file does not match the expected format exactly. "
        "Make sure there are no unnecessary quotes, spaces, or incorrect line endings."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
