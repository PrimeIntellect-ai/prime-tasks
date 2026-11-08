#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

COMBINED_CSV_PATH = "/home/user/combined.csv"
ANOMALIES_CSV_PATH = "/home/user/anomalies.csv"
DB_PATH = "/home/user/analytics.db"

EXPECTED_COMBINED_LINES = [
    "id,timestamp,server_name,response_time_ms",
    "1,2023-10-01T10:00:00Z,srv1,150",
    "2,2023-10-01T10:01:00Z,srv1,155",
    "3,2023-10-01T10:02:00Z,srv1,152",
    "4,2023-10-01T10:03:00Z,srv1,160",
    "5,2023-10-01T10:04:00Z,srv1,500",
    "6,2023-10-01T10:05:00Z,srv1,480",
    "7,2023-10-01T10:06:00Z,srv1,1500",
    "8,2023-10-01T10:07:00Z,srv1,200",
]

EXPECTED_ANOMALIES_LINES = [
    "id,timestamp,server_name,response_time_ms",
    "5,2023-10-01T10:04:00Z,srv1,500",
    "7,2023-10-01T10:06:00Z,srv1,1500",
]

def test_combined_csv():
    assert os.path.isfile(COMBINED_CSV_PATH), f"File {COMBINED_CSV_PATH} is missing."

    with open(COMBINED_CSV_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_COMBINED_LINES, f"{COMBINED_CSV_PATH} content does not match the expected sorted and merged output."

def test_anomalies_csv():
    assert os.path.isfile(ANOMALIES_CSV_PATH), f"File {ANOMALIES_CSV_PATH} is missing."

    with open(ANOMALIES_CSV_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_ANOMALIES_LINES, f"{ANOMALIES_CSV_PATH} content does not match the expected anomalies."

def test_sqlite_database():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Check if table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='performance_logs';")
        assert cursor.fetchone() is not None, "Table 'performance_logs' does not exist in the database."

        # Check data
        cursor.execute("SELECT id, timestamp, server_name, response_time_ms FROM performance_logs ORDER BY timestamp;")
        rows = cursor.fetchall()

        expected_rows = []
        for line in EXPECTED_COMBINED_LINES[1:]:
            parts = line.split(",")
            expected_rows.append((str(parts[0]), parts[1], parts[2], str(parts[3])))

        # Convert fetched rows to string to avoid type mismatch issues (e.g. integer vs string)
        fetched_rows = [(str(r[0]), str(r[1]), str(r[2]), str(r[3])) for r in rows]

        assert fetched_rows == expected_rows, "Data in the 'performance_logs' table does not match the expected combined data."

    except sqlite3.Error as e:
        pytest.fail(f"SQLite error occurred: {e}")
    finally:
        if 'conn' in locals():
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
