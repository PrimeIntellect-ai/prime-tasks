#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import pytest

def test_access_graph_exists():
    assert os.path.isfile('/home/user/access_graph.json'), "Output file /home/user/access_graph.json does not exist."

def test_access_graph_content():
    db_path = '/home/user/employees.db'
    perm_path = '/home/user/permissions.json'
    out_path = '/home/user/access_graph.json'

    assert os.path.isfile(db_path), f"Database file {db_path} is missing."
    assert os.path.isfile(perm_path), f"Permissions file {perm_path} is missing."

    # 1. Read DB
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT emp_id, manager_id FROM org")
    rows = c.fetchall()
    conn.close()

    # 2. Read direct permissions
    with open(perm_path, 'r') as f:
        direct_perms = json.load(f)

    # 3. Compute expected graph
    reports = {}
    employees = set()
    for emp_id, manager_id in rows:
        emp_id_str = str(emp_id)
        employees.add(emp_id_str)
        if manager_id is not None:
            manager_id_str = str(manager_id)
            reports.setdefault(manager_id_str, []).append(emp_id_str)

    def get_all_resources(emp):
        res = set(direct_perms.get(emp, []))
        for report in reports.get(emp, []):
            res.update(get_all_resources(report))
        return res

    expected_graph = {}
    for emp in employees:
        expected_graph[emp] = sorted(list(get_all_resources(emp)))

    # 4. Read actual graph
    with open(out_path, 'r') as f:
        try:
            actual_graph = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{out_path} is not a valid JSON file.")

    assert isinstance(actual_graph, dict), "The output must be a JSON object mapping emp_id to resource lists."

    # 5. Compare
    missing_employees = employees - set(actual_graph.keys())
    assert not missing_employees, f"Missing employees in output: {missing_employees}"

    extra_employees = set(actual_graph.keys()) - employees
    assert not extra_employees, f"Extra unexpected employees in output: {extra_employees}"

    for emp in employees:
        actual_list = actual_graph[emp]
        expected_list = expected_graph[emp]

        assert isinstance(actual_list, list), f"Value for employee {emp} is not a list."
        assert actual_list == expected_list, (
            f"Access list for employee {emp} is incorrect. "
            f"Expected {expected_list}, but got {actual_list}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
