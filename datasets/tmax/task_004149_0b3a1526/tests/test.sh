#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import pytest

HOME = "/home/user"
DB_PATH = os.path.join(HOME, "company.db")
GO_PATH = os.path.join(HOME, "etl.go")
JSON_PATH = os.path.join(HOME, "hierarchy.json")
BINARY_PATH = "/tmp/etl_submission"


def get_expected_tree(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, manager_id, role FROM employees")
    rows = cursor.fetchall()
    conn.close()

    employees = {}
    for row in rows:
        emp = dict(row)
        emp['subordinates'] = []
        employees[emp['id']] = emp

    root = None
    for emp in employees.values():
        manager_id = emp.pop('manager_id')
        if manager_id is None:
            root = emp
        else:
            employees[manager_id]['subordinates'].append(emp)

    return root


def sort_tree(node):
    if 'subordinates' in node and isinstance(node['subordinates'], list):
        node['subordinates'].sort(key=lambda x: x.get('id', 0))
        for sub in node['subordinates']:
            sort_tree(sub)
    return node


def test_01_etl_program_compiles_and_generates_fresh_output():
    assert os.path.isfile(GO_PATH), f"Required Go source file {GO_PATH} does not exist."
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    build = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, GO_PATH],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f"etl.go did not compile successfully:\n{build.stdout}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), "Go build did not produce an executable."

    # Change the raw table after the agent has finished, and remove the stale
    # cache entirely. A prewritten or cache-derived hierarchy cannot satisfy
    # the subsequent database-derived comparison.
    token = secrets.token_hex(16)
    conn = sqlite3.connect(DB_PATH)
    try:
        roots = conn.execute(
            "SELECT id FROM employees WHERE manager_id IS NULL"
        ).fetchall()
        assert len(roots) == 1, "The employees table must contain exactly one root employee."
        root_id = roots[0][0]
        max_id = conn.execute("SELECT COALESCE(MAX(id), 0) FROM employees").fetchone()[0]
        first_id = max_id + 1001
        second_id = max_id + 1002

        conn.execute(
            "UPDATE employees SET name = name || ?, role = role || ?",
            ("-" + token, "-" + token),
        )
        conn.execute(
            "INSERT INTO employees(id, name, manager_id, role) VALUES (?, ?, ?, ?)",
            (first_id, "Verifier-" + token, root_id, "Dynamic Manager-" + token),
        )
        conn.execute(
            "INSERT INTO employees(id, name, manager_id, role) VALUES (?, ?, ?, ?)",
            (second_id, "Nested-" + token, first_id, "Dynamic Report-" + token),
        )
        conn.execute("DROP TABLE IF EXISTS hierarchy_cache")
        conn.commit()
    finally:
        conn.close()

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    run = subprocess.run(
        [BINARY_PATH],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert run.returncode == 0, f"Compiled ETL program failed when executed:\n{run.stdout}"
    assert os.path.isfile(JSON_PATH), f"The executed Go program did not create {JSON_PATH}."


def test_02_hierarchy_json_correct():
    json_path = "/home/user/hierarchy.json"
    db_path = "/home/user/company.db"

    assert os.path.isfile(json_path), f"Output file {json_path} does not exist. The Go program must write to this file."
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            actual_tree = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    expected_tree = get_expected_tree(db_path)

    assert expected_tree is not None, "Failed to compute expected tree (no root employee with manager_id IS NULL found)."

    # Sort subordinates by id for stable comparison
    actual_sorted = sort_tree(actual_tree)
    expected_sorted = sort_tree(expected_tree)

    assert actual_sorted == expected_sorted, "The generated JSON does not match the expected hierarchy derived from the 'employees' table."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
