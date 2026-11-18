#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import pytest

DB_PATH = "/home/user/tracker.db"

def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created."

def test_user_stats_table():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='user_stats';")
    assert cursor.fetchone() is not None, "Table 'user_stats' does not exist."

    # Check data
    cursor.execute("SELECT User, ChangeCount FROM user_stats ORDER BY User;")
    rows = cursor.fetchall()

    expected_rows = [
        ("alice", 3),
        ("bob", 2),
        ("charlie", 1)
    ]

    assert rows == expected_rows, f"Data in 'user_stats' is incorrect. Expected {expected_rows}, got {rows}."
    conn.close()

def test_extracted_ips_table():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='extracted_ips';")
    assert cursor.fetchone() is not None, "Table 'extracted_ips' does not exist."

    # Check data
    cursor.execute("SELECT ChangeID, IP_Address FROM extracted_ips ORDER BY ChangeID, IP_Address;")
    rows = cursor.fetchall()

    expected_rows = [
        ("C001", "192.168.1.100"),
        ("C003", "10.0.0.5"),
        ("C003", "192.168.1.101"),
        ("C005", "172.16.0.42"),
        ("C006", "8.8.8.8")
    ]

    assert rows == expected_rows, f"Data in 'extracted_ips' is incorrect. Expected {expected_rows}, got {rows}."
    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
