#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import sqlite3
import subprocess

import pytest

SCRIPT_FILE = "/home/user/find_violations.py"
VIOLATIONS_FILE = "/home/user/violations.json"
DB_FILE = "/home/user/audit.db"


def file_hash(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def run_script():
    before = file_hash(DB_FILE)
    if os.path.exists(VIOLATIONS_FILE):
        os.remove(VIOLATIONS_FILE)

    result = subprocess.run(
        ["python3", SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"find_violations.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert file_hash(DB_FILE) == before, "find_violations.py modified audit.db."
    assert os.path.isfile(VIOLATIONS_FILE), (
        f"The file {VIOLATIONS_FILE} does not exist. Ensure your script creates it."
    )


def load_output():
    with open(VIOLATIONS_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {VIOLATIONS_FILE} does not contain valid JSON.")


def assert_exact_output(data, expected):
    assert isinstance(data, list), "The JSON output must be a JSON array (list of objects)."
    assert len(data) == len(expected), f"Expected {len(expected)} violations, but found {len(data)}."

    for i, (actual_item, expected_item) in enumerate(zip(data, expected)):
        assert isinstance(actual_item, dict), f"Item at index {i} is not a JSON object."
        actual_keys = set(actual_item.keys())
        expected_keys = set(expected_item.keys())
        assert actual_keys == expected_keys, (
            f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."
        )
        assert actual_item["log_id"] == expected_item["log_id"], (
            f"Item at index {i} has incorrect log_id. Expected {expected_item['log_id']}, "
            f"got {actual_item['log_id']}."
        )
        assert actual_item["employee_name"] == expected_item["employee_name"], (
            f"Item at index {i} has incorrect employee_name. Expected "
            f"'{expected_item['employee_name']}', got '{actual_item['employee_name']}'."
        )
        assert actual_item["resource_name"] == expected_item["resource_name"], (
            f"Item at index {i} has incorrect resource_name. Expected "
            f"'{expected_item['resource_name']}', got '{actual_item['resource_name']}'."
        )

    assert data == expected, f"JSON content mismatch. Expected {expected}, got {data}"


def resolve_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in assignments:
        return resolve_string(assignments[node.id], assignments)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = resolve_string(node.left, assignments)
        right = resolve_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
                return None
            parts.append(value.value)
        return "".join(parts)
    if (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"strip", "lstrip", "rstrip"}
        and not node.args
    ):
        value = resolve_string(node.func.value, assignments)
        if value is not None:
            return getattr(value, node.func.attr)()
    return None


def derive_expected_from_database():
    conn = sqlite3.connect(DB_FILE)
    try:
        employees = {
            row[0]: {"name": row[1], "department": row[2], "manager_id": row[3]}
            for row in conn.execute("SELECT id, name, department, manager_id FROM employees")
        }
        resources = {
            row[0]: {"name": row[1], "sensitivity_level": row[2]}
            for row in conn.execute("SELECT id, name, sensitivity_level FROM resources")
        }
        logs = list(conn.execute("SELECT id, employee_id, resource_id FROM access_logs ORDER BY id"))
    finally:
        conn.close()

    expected = []
    for log_id, employee_id, resource_id in logs:
        resource = resources[resource_id]
        if resource["sensitivity_level"] != 3:
            continue

        allowed = False
        current = employee_id
        visited = set()
        while current is not None and current not in visited:
            visited.add(current)
            employee = employees[current]
            if employee["department"] == "Compliance":
                allowed = True
                break
            current = employee["manager_id"]

        if not allowed:
            expected.append({
                "log_id": log_id,
                "employee_name": employees[employee_id]["name"],
                "resource_name": resource["name"],
            })
    return expected


def test_script_exists_and_uses_one_recursive_sql_query():
    assert os.path.isfile(SCRIPT_FILE), f"The required script {SCRIPT_FILE} does not exist."
    with open(SCRIPT_FILE, "r", encoding="utf-8") as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f"find_violations.py is not valid Python: {exc}")

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            assignments[node.target.id] = node.value

    connect_calls = []
    sql_execution_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and node.func.attr == "connect":
            connect_calls.append(node)
        if isinstance(node.func, ast.Attribute) and node.func.attr in {
            "execute", "executemany", "executescript"
        }:
            sql_execution_calls.append(node)

    assert connect_calls, "The script must connect to the SQLite database."
    assert len(sql_execution_calls) == 1, (
        "The script must execute exactly one SQL query; found "
        f"{len(sql_execution_calls)} SQL execution calls."
    )

    call = sql_execution_calls[0]
    assert call.func.attr == "execute", "The single database operation must be one SQL query."
    assert call.args, "The SQL execute call has no query argument."
    query = resolve_string(call.args[0], assignments)
    assert query is not None, "The SQL passed to execute() must be defined in the script as a string."

    normalized = " ".join(query.upper().split())
    assert "WITH RECURSIVE" in normalized, "The SQL query must use a recursive CTE."
    assert "SELECT" in normalized, "The SQL operation must be a query that selects violations."
    assert normalized.count(" JOIN ") >= 2, (
        "The recursive SQL query must join the employee hierarchy, resources, and access logs."
    )


def test_violations_file_exists():
    run_script()
    assert os.path.isfile(VIOLATIONS_FILE), f"The file {VIOLATIONS_FILE} does not exist. Ensure your script creates it."


def test_violations_content():
    run_script()
    data = load_output()
    expected = [
        {
            "log_id": 2,
            "employee_name": "Eve",
            "resource_name": "Audit_Report_2023"
        },
        {
            "log_id": 5,
            "employee_name": "David",
            "resource_name": "Customer_PII_DB"
        }
    ]
    assert_exact_output(data, expected)


def test_script_computes_results_for_changed_database():
    backup = DB_FILE + ".verifier_backup"
    with open(DB_FILE, "rb") as src, open(backup, "wb") as dst:
        dst.write(src.read())

    try:
        conn = sqlite3.connect(DB_FILE)
        try:
            conn.executemany(
                "INSERT INTO employees (id, name, department, manager_id) VALUES (?, ?, ?, ?)",
                [
                    (8, "Heidi", "Research", 3),
                    (9, "Ivan", "Research", 4),
                    (10, "Judy", "Compliance", 4),
                    (11, "Ken", "Operations", 9),
                ],
            )
            conn.executemany(
                "INSERT INTO resources (id, name, sensitivity_level) VALUES (?, ?, ?)",
                [
                    (105, "Merger_Plans", 3),
                    (106, "Office_Map", 2),
                ],
            )
            conn.executemany(
                "INSERT INTO access_logs (id, employee_id, resource_id, timestamp) VALUES (?, ?, ?, ?)",
                [
                    (7, 8, 105, "2023-10-02T09:00:00Z"),
                    (8, 9, 105, "2023-10-02T10:00:00Z"),
                    (9, 10, 105, "2023-10-02T11:00:00Z"),
                    (10, 11, 105, "2023-10-02T12:00:00Z"),
                    (11, 11, 106, "2023-10-02T13:00:00Z"),
                ],
            )
            conn.commit()
        finally:
            conn.close()

        expected = derive_expected_from_database()
        run_script()
        assert_exact_output(load_output(), expected)
    finally:
        os.replace(backup, DB_FILE)
        if os.path.isfile(SCRIPT_FILE):
            run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
