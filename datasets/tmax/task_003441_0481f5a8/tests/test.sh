#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import json
import pytest

DB_PATH = "/home/user/graph.db"
SCRIPT_PATH = "/home/user/graph_export.py"
EXPORT_PATH = "/home/user/backup_view.json"

def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not created."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

def test_user_db_access_table():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='user_db_access'")
    assert cursor.fetchone() is not None, "Table 'user_db_access' was not created in the database."

    # Check schema
    cursor.execute("PRAGMA table_info(user_db_access)")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    assert "user_name" in columns, "Column 'user_name' missing in 'user_db_access' table."
    assert "db_name" in columns, "Column 'db_name' missing in 'user_db_access' table."

    # Check data matches the expected query
    cursor.execute("SELECT user_name, db_name FROM user_db_access ORDER BY user_name ASC, db_name ASC")
    actual_data = cursor.fetchall()

    # Compute the expected data dynamically from the original tables
    query = """
    SELECT DISTINCT u.name AS user_name, d.name AS db_name
    FROM Nodes u
    JOIN Edges e1 ON u.id = e1.src AND e1.rel = 'MANAGES'
    JOIN Nodes s ON e1.dst = s.id AND s.label = 'Service'
    JOIN Edges e2 ON s.id = e2.src AND e2.rel = 'DEPENDS_ON'
    JOIN Nodes d ON e2.dst = d.id AND d.label = 'Database'
    WHERE u.label = 'User'
    ORDER BY user_name ASC, db_name ASC
    """
    cursor.execute(query)
    expected_data = cursor.fetchall()

    conn.close()

    assert actual_data == expected_data, f"Data in 'user_db_access' table is incorrect. Expected {expected_data}, got {actual_data}."

def test_backup_view_json():
    assert os.path.exists(EXPORT_PATH), f"Export file {EXPORT_PATH} was not created."

    with open(EXPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {EXPORT_PATH} does not contain valid JSON.")

    # Connect to DB to get expected data
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    SELECT DISTINCT u.name AS user_name, d.name AS db_name
    FROM Nodes u
    JOIN Edges e1 ON u.id = e1.src AND e1.rel = 'MANAGES'
    JOIN Nodes s ON e1.dst = s.id AND s.label = 'Service'
    JOIN Edges e2 ON s.id = e2.src AND e2.rel = 'DEPENDS_ON'
    JOIN Nodes d ON e2.dst = d.id AND d.label = 'Database'
    WHERE u.label = 'User'
    ORDER BY user_name ASC, db_name ASC
    """
    cursor.execute(query)
    expected_tuples = cursor.fetchall()
    conn.close()

    expected_json = [{"user": row[0], "database": row[1]} for row in expected_tuples]

    assert data == expected_json, f"JSON data in {EXPORT_PATH} does not match expected output. Expected {expected_json}, got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
