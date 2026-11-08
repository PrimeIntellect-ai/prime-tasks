#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

REPORT_PATH = '/home/user/audit_report.json'
DB_PATH = '/app/corp_audit.db'

def get_expected_scores():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 1. Get the manager of E-9921
    cursor.execute("SELECT manager_id FROM employees WHERE emp_id = 'E-9921'")
    row = cursor.fetchone()
    assert row is not None, "Compromised employee E-9921 not found in database."
    manager_id = row[0]

    # 2. Get the peer group (employees with the same manager)
    cursor.execute("SELECT emp_id FROM employees WHERE manager_id = ?", (manager_id,))
    peers = [r[0] for r in cursor.fetchall()]

    # 3. Get total access counts for peer group, excluding 'Project Chimera'
    placeholders = ','.join('?' for _ in peers)
    query = f"""
        SELECT a.project_name, SUM(a.access_count), p.sensitivity
        FROM access_logs a
        JOIN projects p ON a.project_name = p.project_name
        WHERE a.emp_id IN ({placeholders})
          AND a.project_name != 'Project Chimera'
        GROUP BY a.project_name
    """
    cursor.execute(query, peers)

    expected_scores = {}
    for proj_name, total_access, sensitivity in cursor.fetchall():
        expected_scores[proj_name] = total_access * sensitivity

    conn.close()
    return expected_scores

def test_audit_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file"

def test_audit_report_contents():
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The audit report is not valid JSON.")

    assert "compromised_employee" in data, "Missing 'compromised_employee' in report."
    assert "compromised_project" in data, "Missing 'compromised_project' in report."
    assert "risk_scores" in data, "Missing 'risk_scores' in report."

    emp = data["compromised_employee"]
    proj = data["compromised_project"]

    assert emp == "E-9921", f"Expected compromised_employee 'E-9921', got '{emp}'"
    assert proj == "Project Chimera", f"Expected compromised_project 'Project Chimera', got '{proj}'"

    expected_scores = get_expected_scores()
    agent_scores = data.get("risk_scores", {})

    assert isinstance(agent_scores, dict), "'risk_scores' should be a dictionary."
    assert set(agent_scores.keys()) == set(expected_scores.keys()), (
        f"Risk score project keys do not match expected projects. "
        f"Expected {sorted(expected_scores.keys())}, got {sorted(agent_scores.keys())}"
    )

    keys = set(list(expected_scores.keys()) + list(agent_scores.keys()))
    if not keys:
        mae = 0.0
    else:
        mae = 0.0
        for k in keys:
            expected_val = expected_scores.get(k, 0.0)
            agent_val = agent_scores.get(k, 0.0)
            try:
                agent_val = float(agent_val)
            except (ValueError, TypeError):
                pytest.fail(f"Risk score for {k} is not a valid number: {agent_val}")
            mae += abs(expected_val - agent_val)
        mae = mae / len(keys)

    accuracy = max(0.0, 1.0 - (mae / 10.0))

    assert accuracy >= 0.9, f"Accuracy metric {accuracy} is below the threshold of 0.9 (MAE: {mae})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
