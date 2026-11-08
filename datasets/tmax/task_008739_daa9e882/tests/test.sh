#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

VIOLATIONS_JSON_PATH = '/home/user/violations.json'
DB_PATH = '/home/user/audit.db'

def get_expected_violations():
    """
    Derive the expected violations directly from the database to ensure correctness
    based on the intent of the task.
    """
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    query = """
    SELECT 
        a.log_id, 
        a.emp_id, 
        e.name, 
        a.system_name, 
        a.access_time
    FROM access_logs a
    JOIN employees e ON a.emp_id = e.emp_id
    LEFT JOIN certifications c ON a.emp_id = c.emp_id AND a.system_name = c.system_name
    WHERE a.status = 'GRANTED'
      AND (c.cert_id IS NULL OR a.access_time > c.expiration_date)
    ORDER BY a.log_id ASC
    """
    c.execute(query)
    rows = c.fetchall()
    conn.close()

    expected = []
    for row in rows:
        expected.append({
            "log_id": row["log_id"],
            "emp_id": row["emp_id"],
            "name": row["name"],
            "system_name": row["system_name"],
            "access_time": row["access_time"]
        })
    return expected

def test_violations_json_exists():
    """Test that the violations.json file was created."""
    assert os.path.exists(VIOLATIONS_JSON_PATH), f"Expected output file not found at {VIOLATIONS_JSON_PATH}"

def test_violations_json_content():
    """Test that the violations.json file contains the correct data."""
    assert os.path.exists(VIOLATIONS_JSON_PATH), f"Expected output file not found at {VIOLATIONS_JSON_PATH}"

    with open(VIOLATIONS_JSON_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {VIOLATIONS_JSON_PATH} is not valid JSON.")

    expected_data = get_expected_violations()

    assert isinstance(actual_data, list), f"Expected JSON root to be a list, got {type(actual_data).__name__}"
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} violations, found {len(actual_data)}"

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}. Expected: {expected}, Actual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
