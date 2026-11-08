#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

DB_PATH = '/home/user/compliance_audit.db'
REPORT_PATH = '/home/user/audit_report.json'

def compute_pagerank(nodes, edges, alpha=0.85, max_iter=100):
    """Computes PageRank exactly as networkx.pagerank does by default."""
    N = len(nodes)
    if N == 0:
        return {}

    pr = {n: 1.0 / N for n in nodes}
    out_degree = {n: 0 for n in nodes}
    for u, v in edges:
        out_degree[u] += 1

    for _ in range(max_iter):
        new_pr = {n: (1.0 - alpha) / N for n in nodes}
        dangling_sum = sum(pr[n] for n in nodes if out_degree[n] == 0)
        dangling_dist = alpha * dangling_sum / N

        for n in nodes:
            new_pr[n] += dangling_dist

        for u, v in edges:
            new_pr[v] += alpha * pr[u] / out_degree[u]

        pr = new_pr

    return pr

def test_audit_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."

def test_audit_report_content():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} missing, cannot verify report."

    # 1. Recompute the expected truth from the database
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Get employees
    cur.execute("SELECT emp_id, name FROM employees")
    employees = {row[0]: row[1] for row in cur.fetchall()}

    # Get communications
    cur.execute("SELECT sender_id, receiver_id FROM communications")
    edges = cur.fetchall()

    # Compute PageRank
    pr_scores = compute_pagerank(list(employees.keys()), edges)

    # Sort to find top 3
    sorted_emps = sorted(pr_scores.items(), key=lambda x: (-x[1], x[0]))
    top_3 = sorted_emps[:3]

    # Get latest high risk system for top 3
    expected_results = []
    for emp_id, pr in top_3:
        cur.execute('''
            SELECT s.sys_name
            FROM access_logs a
            JOIN systems s ON a.sys_id = s.sys_id
            WHERE a.emp_id = ? AND s.sensitivity = 'High'
            ORDER BY a.access_time DESC
            LIMIT 1
        ''', (emp_id,))
        row = cur.fetchone()
        sys_name = row[0] if row else None

        expected_results.append({
            "employee_id": emp_id,
            "employee_name": employees[emp_id],
            "pagerank_score": round(pr, 4),
            "latest_high_risk_system": sys_name
        })

    conn.close()

    # 2. Read and validate the student's JSON
    try:
        with open(REPORT_PATH, 'r') as f:
            student_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{REPORT_PATH} is not valid JSON.")

    assert isinstance(student_data, list), "JSON output must be a list of objects."
    assert len(student_data) == 3, f"Expected exactly 3 records, got {len(student_data)}."

    # 3. Compare student's output to expected
    for i, expected in enumerate(expected_results):
        student_record = student_data[i]

        assert "employee_id" in student_record, f"Record {i} missing 'employee_id'"
        assert "employee_name" in student_record, f"Record {i} missing 'employee_name'"
        assert "pagerank_score" in student_record, f"Record {i} missing 'pagerank_score'"
        assert "latest_high_risk_system" in student_record, f"Record {i} missing 'latest_high_risk_system'"

        assert student_record["employee_id"] == expected["employee_id"], \
            f"Expected employee_id {expected['employee_id']} at rank {i+1}, got {student_record['employee_id']}"

        assert student_record["employee_name"] == expected["employee_name"], \
            f"Expected employee_name '{expected['employee_name']}', got '{student_record['employee_name']}'"

        assert student_record["latest_high_risk_system"] == expected["latest_high_risk_system"], \
            f"Expected system '{expected['latest_high_risk_system']}', got '{student_record['latest_high_risk_system']}'"

        # Check PageRank with a small tolerance for float math differences
        expected_pr = expected["pagerank_score"]
        student_pr = student_record["pagerank_score"]
        assert abs(student_pr - expected_pr) <= 0.005, \
            f"PageRank score for {expected['employee_name']} is {student_pr}, expected ~{expected_pr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
