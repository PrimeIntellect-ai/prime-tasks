#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

DB_PATH = '/home/user/cleaned_data.db'

def test_database_exists():
    """Check if the SQLite database was created."""
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"

def test_table_exists():
    """Check if the employee_projects table exists in the database."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='employee_projects';")
    table = c.fetchone()
    conn.close()
    assert table is not None, "Table 'employee_projects' does not exist in the database."

def test_schema_correctness():
    """Check if the table has the correct schema (columns)."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("PRAGMA table_info(employee_projects)")
    schema = c.fetchall()
    conn.close()

    columns = [col[1] for col in schema]
    expected_columns = ['ID', 'Name', 'Department', 'Salary', 'Project_Name', 'Start_Date']
    assert columns == expected_columns, f"Schema mismatch. Expected {expected_columns}, got {columns}"

def test_data_correctness():
    """Check if the data has been cleaned, joined, and inserted correctly."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT * FROM employee_projects ORDER BY ID")
    rows = c.fetchall()
    conn.close()

    expected = [
        (1, 'Alice', 'Engineering', 80000.0, 'Alpha', '2023-01-15'),
        (2, 'Bob', 'Engineering', 80000.0, 'Beta', '2023-02-20'),
        (3, 'Charlie', 'Sales', 50000.0, 'Gamma', '2023-03-05'),
        (5, 'Eve', 'HR', 60000.0, 'Epsilon', '2023-04-10')
    ]

    assert len(rows) == len(expected), f"Expected {len(expected)} rows, but got {len(rows)} rows."

    for i, (actual_row, expected_row) in enumerate(zip(rows, expected)):
        assert actual_row == expected_row, f"Row {i} mismatch. Expected {expected_row}, got {actual_row}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
