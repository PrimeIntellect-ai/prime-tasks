#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import hashlib
import csv
from collections import defaultdict

DB_PATH = "/home/user/configs.db"
REPORT_PATH = "/home/user/report.csv"

def normalize_config(text):
    if not text:
        return ""
    lines = text.split('\n')
    normalized_lines = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith('#'):
            continue
        normalized_lines.append(stripped)
    return '\n'.join(normalized_lines)

def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"

def test_report_contents():
    # Derive expected output from the database
    assert os.path.exists(DB_PATH), "Database file missing, cannot verify."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT hostname, config_text FROM server_configs")
    rows = cursor.fetchall()
    conn.close()

    # Group by hostname and count unique hashes
    host_hashes = defaultdict(set)
    for hostname, config_text in rows:
        normalized = normalize_config(config_text)
        config_hash = hashlib.sha256(normalized.encode('utf-8')).hexdigest()
        host_hashes[hostname].add(config_hash)

    expected_counts = {host: len(hashes) for host, hashes in host_hashes.items()}

    # Sort: descending by unique_configs, ascending by hostname
    sorted_expected = sorted(expected_counts.items(), key=lambda x: (-x[1], x[0]))

    # Read actual report
    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "Report CSV is empty"

    # Check header
    assert actual_rows[0] == ['hostname', 'unique_configs'], "CSV header is incorrect"

    # Check data
    actual_data = actual_rows[1:]
    assert len(actual_data) == len(sorted_expected), "Incorrect number of rows in the report"

    for i, (expected_host, expected_count) in enumerate(sorted_expected):
        actual_host = actual_data[i][0]
        actual_count = actual_data[i][1]

        assert actual_host == expected_host, f"Row {i+1}: Expected hostname '{expected_host}', got '{actual_host}'"
        assert str(actual_count) == str(expected_count), f"Row {i+1} for {expected_host}: Expected count {expected_count}, got {actual_count}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
