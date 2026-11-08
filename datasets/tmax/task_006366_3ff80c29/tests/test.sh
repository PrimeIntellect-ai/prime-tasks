#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import re

def test_database_exists():
    db_path = "/home/user/processed_logs.db"
    assert os.path.exists(db_path), f"Database file not found at {db_path}"
    assert os.path.isfile(db_path), f"Expected a file at {db_path}"

def test_table_schema():
    db_path = "/home/user/processed_logs.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='normalized_logs';")
    table = cursor.fetchone()
    assert table is not None, "Table 'normalized_logs' does not exist in the database."

    cursor.execute("PRAGMA table_info(normalized_logs);")
    columns = cursor.fetchall()

    expected_columns = ["date", "level", "user_id", "message"]
    actual_columns = [col[1] for col in columns]

    assert actual_columns == expected_columns, f"Expected columns {expected_columns}, but got {actual_columns}"
    conn.close()

def compute_expected_data():
    raw_logs_path = "/home/user/raw_logs.txt"
    assert os.path.exists(raw_logs_path), f"Raw logs file missing: {raw_logs_path}"

    expected_rows = []

    # Regex to match the strict format: [YYYY/MM/DD] [LEVEL] <UserID> - Message
    # Date: \[\d{4}/\d{2}/\d{2}\]
    # Level: \[(INFO|WARN|ERROR)\]
    # UserID: <[A-Za-z0-9]{8}>
    # Separator:  - 
    # Message: .*
    pattern = re.compile(r'^\[(\d{4}/\d{2}/\d{2})\] \[(INFO|WARN|ERROR)\] <([A-Za-z0-9]{8})> - (.*)$')

    with open(raw_logs_path, 'r') as f:
        for line in f:
            line = line.strip('\n')
            match = pattern.match(line)
            if match:
                date_raw, level, user_id, message_raw = match.groups()
                date_norm = date_raw.replace('/', '-')
                message_norm = message_raw.lower()
                expected_rows.append((date_norm, level, user_id, message_norm))

    return expected_rows

def test_database_content():
    db_path = "/home/user/processed_logs.db"
    expected_data = compute_expected_data()

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT date, level, user_id, message FROM normalized_logs ORDER BY date ASC, user_id ASC;")
    actual_data = cursor.fetchall()
    conn.close()

    expected_data_sorted = sorted(expected_data, key=lambda x: (x[0], x[2]))

    assert len(actual_data) == len(expected_data_sorted), f"Expected {len(expected_data_sorted)} rows, but got {len(actual_data)} rows."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data_sorted)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
