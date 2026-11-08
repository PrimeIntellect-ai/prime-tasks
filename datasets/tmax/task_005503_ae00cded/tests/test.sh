#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import pytest

REPORT_PATH = '/home/user/compliance_report.json'
DB_PATH = '/home/user/audit.db'

def get_expected_results():
    """Derive the expected top employee and system from the database."""
    if not os.path.exists(DB_PATH):
        # Fallback to known truth if DB is somehow missing, though it shouldn't be
        return 101, 40

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Top employee: highest out-degree (most unique systems accessed)
    c.execute('''
        SELECT e_id, COUNT(DISTINCT s_id) as out_degree 
        FROM log 
        GROUP BY e_id 
        ORDER BY out_degree DESC, e_id ASC 
        LIMIT 1
    ''')
    top_emp_row = c.fetchone()
    top_emp = top_emp_row[0] if top_emp_row else 101

    # Top system: highest PageRank. In a directed bipartite graph (Emp -> Sys),
    # the system with the highest in-degree will have the highest PageRank.
    c.execute('''
        SELECT s_id, COUNT(DISTINCT e_id) as in_degree 
        FROM log 
        GROUP BY s_id 
        ORDER BY in_degree DESC, s_id ASC 
        LIMIT 1
    ''')
    top_sys_row = c.fetchone()
    top_sys = top_sys_row[0] if top_sys_row else 40

    conn.close()
    return top_emp, top_sys

def test_compliance_report_exists():
    """Test that the compliance_report.json file was created."""
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"The path {REPORT_PATH} is not a file."

def test_compliance_report_content():
    """Test that the compliance report contains the correct JSON structure and values."""
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} is missing."

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON in {REPORT_PATH}: {e}")

    assert isinstance(data, dict), f"Expected JSON root to be an object (dict), got {type(data).__name__}"

    assert "top_employee_id" in data, "Missing key 'top_employee_id' in the JSON report"
    assert "top_system_id" in data, "Missing key 'top_system_id' in the JSON report"

    expected_emp, expected_sys = get_expected_results()

    assert data["top_employee_id"] == expected_emp, (
        f"Incorrect top_employee_id. Expected {expected_emp}, got {data['top_employee_id']}"
    )
    assert data["top_system_id"] == expected_sys, (
        f"Incorrect top_system_id. Expected {expected_sys}, got {data['top_system_id']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
