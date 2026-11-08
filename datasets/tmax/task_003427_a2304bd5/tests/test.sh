#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import pytest

DB_PATH = "/home/user/employees.db"
JSON_PATH = "/home/user/transfers.json"
REPORT_PATH = "/home/user/audit_report.json"

EXPECTED_DEPARTMENTS = [
    (1, "Sales"),
    (2, "Engineering"),
    (3, "HR"),
    (4, "Executive"),
]

EXPECTED_EMPLOYEES = [
    (1, "Alice", 1),
    (2, "Bob", 1),
    (3, "Charlie", 2),
    (4, "David", 2),
    (5, "Eve", 2),
    (6, "Frank", 3),
    (7, "Grace", 3),
    (8, "Heidi", 4),
    (9, "Ivan", 4),
    (10, "Judy", 1),
]

EXPECTED_TRANSFERS = [
    {"source_emp_id": 1, "dest_emp_id": 3, "amount": 100, "timestamp": "2023-10-01T10:00:00Z"},
    {"source_emp_id": 3, "dest_emp_id": 4, "amount": 200, "timestamp": "2023-10-01T11:00:00Z"},
    {"source_emp_id": 4, "dest_emp_id": 5, "amount": 300, "timestamp": "2023-10-01T12:00:00Z"},
    {"source_emp_id": 5, "dest_emp_id": 6, "amount": 400, "timestamp": "2023-10-01T13:00:00Z"},
    {"source_emp_id": 2, "dest_emp_id": 1, "amount": 500, "timestamp": "2023-10-01T14:00:00Z"},
    {"source_emp_id": 2, "dest_emp_id": 10, "amount": 600, "timestamp": "2023-10-01T15:00:00Z"},
    {"source_emp_id": 8, "dest_emp_id": 9, "amount": 700, "timestamp": "2023-10-01T16:00:00Z"},
    {"source_emp_id": 9, "dest_emp_id": 8, "amount": 800, "timestamp": "2023-10-01T17:00:00Z"},
]

def get_db_data():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} is missing.")
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT id, name, department_id FROM employees")
        employees = c.fetchall()
        c.execute("SELECT id, name FROM departments")
        departments = c.fetchall()
        return employees, departments
    finally:
        conn.close()

def get_transfers():
    if not os.path.exists(JSON_PATH):
        pytest.fail(f"JSON file {JSON_PATH} is missing.")
    try:
        with open(JSON_PATH, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as exc:
        pytest.fail(f"Could not read valid transfer fixture: {exc}")

def test_source_fixtures_intact():
    employees, departments = get_db_data()
    transfers = get_transfers()

    assert sorted(employees) == EXPECTED_EMPLOYEES, \
        "The employees source fixture was modified."
    assert sorted(departments) == EXPECTED_DEPARTMENTS, \
        "The departments source fixture was modified."
    assert transfers == EXPECTED_TRANSFERS, \
        "The transfers source fixture was modified."

def compute_expected_reach():
    emp_ids = [e[0] for e in EXPECTED_EMPLOYEES]
    adj = {eid: set() for eid in emp_ids}
    for transfer in EXPECTED_TRANSFERS:
        src = transfer["source_emp_id"]
        dst = transfer["dest_emp_id"]
        if src in adj:
            adj[src].add(dst)

    reach = {}
    for eid in emp_ids:
        visited = set()
        stack = list(adj[eid])
        while stack:
            curr = stack.pop()
            if curr not in visited:
                visited.add(curr)
                if curr in adj:
                    stack.extend(adj[curr])
        visited.discard(eid)
        reach[eid] = len(visited)
    return reach

def compute_expected_report():
    dep_map = {did: name for did, name in EXPECTED_DEPARTMENTS}
    reach = compute_expected_reach()
    dep_emps = {did: [] for did, _ in EXPECTED_DEPARTMENTS}

    for eid, name, did in EXPECTED_EMPLOYEES:
        dep_emps[did].append({
            "emp_id": eid,
            "employee_name": name,
            "reach": reach[eid],
        })

    report = []
    for did, emps in dep_emps.items():
        emps.sort(key=lambda x: (-x["reach"], x["emp_id"]))
        # DENSE_RANK over (reach DESC, emp_id ASC). Because emp_id is unique,
        # each complete ordering tuple has a distinct rank, including reach ties.
        for index, emp in enumerate(emps):
            department_rank = index + 1
            if department_rank <= 2:
                report.append({
                    "department_name": dep_map[did],
                    "emp_id": emp["emp_id"],
                    "employee_name": emp["employee_name"],
                    "reach": emp["reach"],
                    "department_rank": department_rank,
                })

    report.sort(key=lambda x: (x["department_name"], x["department_rank"], x["emp_id"]))
    return report

def test_reach_metrics_table():
    expected_reach = compute_expected_reach()

    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='reach_metrics';")
        if not c.fetchone():
            pytest.fail("Table 'reach_metrics' was not created in employees.db.")

        c.execute("SELECT emp_id, reach FROM reach_metrics")
        actual_reach = dict(c.fetchall())
    finally:
        conn.close()

    for eid, expected_val in expected_reach.items():
        assert eid in actual_reach, f"Employee ID {eid} missing from reach_metrics table."
        assert actual_reach[eid] == expected_val, \
            f"Incorrect reach for employee {eid}. Expected {expected_val}, got {actual_reach[eid]}."

    assert set(actual_reach) == set(expected_reach), \
        "reach_metrics contains rows for unknown or missing employees."

def test_audit_report_json():
    if not os.path.exists(REPORT_PATH):
        pytest.fail(f"Audit report file {REPORT_PATH} is missing.")

    with open(REPORT_PATH, "r") as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    expected_report = compute_expected_report()

    assert isinstance(actual_report, list), "Audit report must be a JSON array."
    assert len(actual_report) == len(expected_report), \
        f"Expected {len(expected_report)} records in audit report, got {len(actual_report)}."

    for i, (actual, expected) in enumerate(zip(actual_report, expected_report)):
        assert actual == expected, \
            f"Mismatch at index {i} in audit report.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
