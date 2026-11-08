#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

DB_PATH = '/home/user/etl/source.db'
OUTPUT_JSON_PATH = '/home/user/etl/output/dept_summary.json'

def compute_expected_data():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database {DB_PATH} is missing, cannot compute expected data.")

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Fetch departments
    c.execute("SELECT uid, moniker FROM t_alpha")
    departments = {row[0]: row[1] for row in c.fetchall()}

    # Fetch employees
    c.execute("SELECT eid, ename, alpha_id FROM t_beta")
    employees = c.fetchall()
    N = len(employees)

    if N <= 1:
        pytest.fail("Not enough employees to compute centrality.")

    employee_depts = {row[0]: row[2] for row in employees}
    employee_names = {row[0]: row[1] for row in employees}

    # Fetch messages and compute unique incoming edges
    c.execute("SELECT s_id, r_id FROM t_gamma")
    edges = set(c.fetchall())

    in_degrees = {row[0]: 0 for row in employees}
    for s_id, r_id in edges:
        if r_id in in_degrees:
            in_degrees[r_id] += 1

    # Compute centralities
    centralities = {eid: round(deg / (N - 1), 4) for eid, deg in in_degrees.items()}

    # Group by department
    dept_employees = {}
    for eid, dept_id in employee_depts.items():
        if dept_id not in dept_employees:
            dept_employees[dept_id] = []
        dept_employees[dept_id].append({
            "name": employee_names[eid],
            "centrality": centralities[eid]
        })

    # Filter and aggregate
    expected_result = []
    for dept_id, emps in dept_employees.items():
        if len(emps) < 2:
            continue

        avg_cent = round(sum(e["centrality"] for e in emps) / len(emps), 4)

        # Sort employees: centrality DESC, name ASC
        sorted_emps = sorted(emps, key=lambda x: (-x["centrality"], x["name"]))
        top_emps = sorted_emps[:2]

        expected_result.append({
            "department_name": departments[dept_id],
            "average_centrality": avg_cent,
            "top_employees": top_emps
        })

    # Sort departments: average_centrality DESC, name ASC
    expected_result.sort(key=lambda x: (-x["average_centrality"], x["department_name"]))

    conn.close()
    return expected_result

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_JSON_PATH), f"The final output file {OUTPUT_JSON_PATH} was not found."

def test_output_json_structure_and_values():
    expected_data = compute_expected_data()

    with open(OUTPUT_JSON_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_JSON_PATH} does not contain valid JSON.")

    assert isinstance(actual_data, list), "The output JSON must be a list of department objects."

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} departments after filtering, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert "department_name" in actual, f"Missing 'department_name' in item {i}"
        assert "average_centrality" in actual, f"Missing 'average_centrality' in item {i}"
        assert "top_employees" in actual, f"Missing 'top_employees' in item {i}"

        assert actual["department_name"] == expected["department_name"], \
            f"Expected department '{expected['department_name']}' at index {i}, got '{actual['department_name']}'."

        assert actual["average_centrality"] == expected["average_centrality"], \
            f"Expected average_centrality {expected['average_centrality']} for {actual['department_name']}, got {actual['average_centrality']}."

        assert isinstance(actual["top_employees"], list), f"'top_employees' must be a list in {actual['department_name']}."
        assert len(actual["top_employees"]) == len(expected["top_employees"]), \
            f"Expected {len(expected['top_employees'])} top employees in {actual['department_name']}, got {len(actual['top_employees'])}."

        for j, (actual_emp, expected_emp) in enumerate(zip(actual["top_employees"], expected["top_employees"])):
            assert "name" in actual_emp, f"Missing 'name' in employee {j} of {actual['department_name']}"
            assert "centrality" in actual_emp, f"Missing 'centrality' in employee {j} of {actual['department_name']}"

            assert actual_emp["name"] == expected_emp["name"], \
                f"Expected employee name '{expected_emp['name']}', got '{actual_emp['name']}'."
            assert actual_emp["centrality"] == expected_emp["centrality"], \
                f"Expected centrality {expected_emp['centrality']} for {actual_emp['name']}, got {actual_emp['centrality']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
