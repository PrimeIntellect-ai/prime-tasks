#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

ANONYMIZED_FILE = "/home/user/anonymized_events.txt"
CSV_FILE = "/home/user/march_daily_changes.csv"

def test_anonymized_events_exists():
    assert os.path.isfile(ANONYMIZED_FILE), f"Missing output file: {ANONYMIZED_FILE}"

def test_march_daily_changes_exists():
    assert os.path.isfile(CSV_FILE), f"Missing output file: {CSV_FILE}"

def test_anonymized_events_content():
    expected_lines = [
        "2024-03-01T09:00:00Z | XXX.XXX.XXX.XXX | MASKED_USER | START | system boot",
        "2024-03-01T10:15:22Z | XXX.XXX.XXX.XXX | MASKED_USER | UPDATE | param=1",
        "2024-03-02T11:00:00Z | XXX.XXX.XXX.XXX | MASKED_USER | RESTART | ",
        "2024-03-05T14:32:01Z | XXX.XXX.XXX.XXX | MASKED_USER | UPDATE | changed max_connections to 500",
        "2024-03-15T00:00:00Z | XXX.XXX.XXX.XXX | MASKED_USER | DELETE | old_logs",
        "2024-03-15T01:00:00Z | XXX.XXX.XXX.XXX | MASKED_USER | DELETE | temp_files",
        "2024-03-15T02:00:00Z | XXX.XXX.XXX.XXX | MASKED_USER | DELETE | cache",
        "2024-03-31T23:59:59Z | XXX.XXX.XXX.XXX | MASKED_USER | STOP | system shutdown"
    ]

    with open(ANONYMIZED_FILE, "r") as f:
        content = f.read().strip().split('\n')

    # Remove any empty lines at the end
    content = [line for line in content if line]

    assert content == expected_lines, (
        f"Contents of {ANONYMIZED_FILE} do not match the expected anonymized output. "
        "Check filtering (exactly 5 pipe-separated fields, March 2024 only) and anonymization (IP and Username)."
    )

def test_march_daily_changes_content():
    expected_counts = {
        "2024-03-01": 2,
        "2024-03-02": 1,
        "2024-03-05": 1,
        "2024-03-15": 3,
        "2024-03-31": 1
    }

    expected_lines = []
    for day in range(1, 32):
        date_str = f"2024-03-{day:02d}"
        count = expected_counts.get(date_str, 0)
        expected_lines.append(f"{date_str},{count}")

    with open(CSV_FILE, "r") as f:
        content = f.read().strip().split('\n')

    # Remove any empty lines
    content = [line for line in content if line]

    # Check if header is present, if so, ignore it for exact match but warn
    if content and content[0].lower() == "date,count":
        content = content[1:]

    assert content == expected_lines, (
        f"Contents of {CSV_FILE} do not match the expected time series. "
        "Ensure every day from 2024-03-01 to 2024-03-31 is present sequentially with correct valid event counts."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
