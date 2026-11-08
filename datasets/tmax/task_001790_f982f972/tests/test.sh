#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

LOCAL_LOGS_DIR = "/home/user/local_logs"
CSV_PATH = "/home/user/suspicious_activity.csv"

def test_local_logs_directory_exists():
    assert os.path.isdir(LOCAL_LOGS_DIR), f"Directory {LOCAL_LOGS_DIR} does not exist. Did you copy the logs?"

def test_local_logs_are_utf8():
    expected_files = ["server_alpha.log", "server_beta.log", "server_gamma.log"]
    for filename in expected_files:
        filepath = os.path.join(LOCAL_LOGS_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."

        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {filepath} is not properly encoded in UTF-8.")

def test_csv_exists():
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist."

def test_csv_content():
    expected_rows = [
        ["2023-10-11T12:00:00Z", "192.168.1.10", "502"],
        ["2023-10-11T12:05:00Z", "172.16.0.4", "404"],
        ["2023-10-11T12:10:00Z", "192.168.1.10", "403"],
        ["2023-10-11T13:13:20Z", "192.168.2.50", "401"],
        ["2023-10-11T14:00:00Z", "10.1.2.3", "500"],
        ["2023-10-13T09:15:00Z", "172.16.1.99", "503"]
    ]

    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    expected_header = ["Timestamp", "IP_Address", "Error_Code"]
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, got {len(data_rows)}"

    # Check if rows are sorted chronologically
    timestamps = [row[0] for row in data_rows]
    assert timestamps == sorted(timestamps), "CSV rows are not sorted chronologically by timestamp."

    # Check exact content
    for expected, actual in zip(expected_rows, data_rows):
        assert actual == expected, f"Row mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
