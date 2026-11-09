#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

CSV_PATH = "/home/user/config_audit.csv"

def test_csv_file_exists():
    assert os.path.isfile(CSV_PATH), f"The expected output file {CSV_PATH} does not exist."

def test_no_carriage_returns():
    with open(CSV_PATH, "rb") as f:
        content = f.read()
    assert b"\r" not in content, f"The file {CSV_PATH} contains carriage returns (\\r). Only standard unix line endings (\\n) are allowed."

def test_csv_header():
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)

    assert header is not None, "The CSV file is empty, missing a header."
    assert header == ["date", "app", "key", "value"], f"The CSV header is incorrect. Expected ['date', 'app', 'key', 'value'], got {header}."

def test_csv_content_and_sorting():
    # Derive the expected data based on the task description and initial state
    expected_records = [
        ["2023-10-01", "app1", "hostname", "prod-db"],
        ["2023-10-01", "app1", "password", "[REDACTED]"],
        ["2023-10-01", "app1", "port", "5432"],
        ["2023-10-01", "app2", "status", "missing"],

        ["2023-10-02", "app1", "status", "missing"],
        ["2023-10-02", "app2", "apikey", "[REDACTED]"],
        ["2023-10-02", "app2", "endpoint", "https://api.example.com"],
        ["2023-10-02", "app2", "retrycount", "3"],

        ["2023-10-03", "app1", "hostname", "prod-db"],
        ["2023-10-03", "app1", "password", "[REDACTED]"],
        ["2023-10-03", "app1", "port", "5432"],
        ["2023-10-03", "app2", "status", "missing"],

        ["2023-10-04", "app1", "status", "missing"],
        ["2023-10-04", "app2", "status", "missing"],

        ["2023-10-05", "app1", "status", "missing"],
        ["2023-10-05", "app2", "apikey", "[REDACTED]"],
        ["2023-10-05", "app2", "endpoint", "https://api.example.com"],
        ["2023-10-05", "app2", "retrycount", "5"],
    ]

    # Sort expected records to ensure strict adherence to sorting rules
    expected_records.sort(key=lambda x: (x[0], x[1], x[2]))

    actual_records = []
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)  # Skip header
        for row in reader:
            actual_records.append(row)

    # Check that actual records are sorted
    sorted_actual = sorted(actual_records, key=lambda x: (x[0], x[1], x[2]))
    assert actual_records == sorted_actual, "The CSV data rows are not sorted alphabetically by date, then app, then key."

    # Compare content
    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} data rows, but found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, f"Row {i+2} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
