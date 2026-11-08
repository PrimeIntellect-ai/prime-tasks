#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_instrumented.py
import json
import runpy
import sqlite3
import sys

script_path = sys.argv[1]
trace_path = sys.argv[2]
statements = []
original_connect = sqlite3.connect

class TracedConnection(sqlite3.Connection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        super().set_trace_callback(statements.append)

    def set_trace_callback(self, callback):
        if callback is None:
            return super().set_trace_callback(statements.append)

        def combined(statement):
            statements.append(statement)
            callback(statement)
        return super().set_trace_callback(combined)

def traced_connect(*args, **kwargs):
    if len(args) > 5 or "factory" in kwargs:
        raise RuntimeError("Custom SQLite connection factories are not supported during verification")
    kwargs["factory"] = TracedConnection
    return original_connect(*args, **kwargs)

sqlite3.connect = traced_connect
try:
    runpy.run_path(script_path, run_name="__main__")
finally:
    with open(trace_path, "w", encoding="utf-8") as f:
        json.dump(statements, f)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = "/home/user/optimize_graph.py"
DB_PATH = "/home/user/corp.db"
OUTPUT_JSON_PATH = "/home/user/graph_output.json"
RUNNER_PATH = "/tmp/run_instrumented.py"
TRACE_PATH = "/tmp/optimize_graph_trace.json"
BACKUP_PATH = "/tmp/corp.db.verifier-backup"


def database_snapshot():
    with sqlite3.connect(DB_PATH) as conn:
        schema = conn.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        departments = conn.execute(
            "SELECT dept_id, dept_name FROM departments ORDER BY dept_id"
        ).fetchall()
        employees = conn.execute(
            "SELECT emp_id, name, manager_id, dept_id FROM employees ORDER BY emp_id"
        ).fetchall()
    return schema, departments, employees


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    result = subprocess.run(
        ["python3", RUNNER_PATH, SCRIPT_PATH, TRACE_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"optimize_graph.py failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_JSON_PATH), (
        f"Running {SCRIPT_PATH} did not create {OUTPUT_JSON_PATH}"
    )

    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        statements = json.load(f)
    assert len(statements) == 1, (
        f"The script must execute exactly one SQL statement; observed {len(statements)}: {statements}"
    )

    sql = re.sub(r"/\*.*?\*/", " ", statements[0], flags=re.DOTALL)
    sql = re.sub(r"--[^\n]*", " ", sql).strip()
    assert re.match(r"(?is)^WITH\s+RECURSIVE\b", sql), (
        "The single SQL statement must begin with a recursive CTE"
    )
    assert re.search(r"(?i)\bdepartments\b", sql), (
        "The recursive query must retrieve department data from the departments table"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_preserve_database():
    shutil.copy2(DB_PATH, BACKUP_PATH)
    try:
        before = database_snapshot()
        run_submission()
        after = database_snapshot()
        assert after == before, "The submission modified the database schema or data"
        yield
    finally:
        shutil.copy2(BACKUP_PATH, DB_PATH)


def test_json_output_exists():
    """Check if the output JSON file exists."""
    assert os.path.isfile(OUTPUT_JSON_PATH), f"Output JSON file missing at {OUTPUT_JSON_PATH}"


def test_json_output_content():
    """Check if the output JSON file contains the correct hierarchy data."""
    with open(OUTPUT_JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_JSON_PATH} does not contain valid JSON.")

    expected_data = [
        {"emp_id": 1, "name": "Alice", "manager_id": None, "department": "Executive", "depth": 0},
        {"emp_id": 2, "name": "Bob", "manager_id": 1, "department": "Engineering", "depth": 1},
        {"emp_id": 3, "name": "Charlie", "manager_id": 1, "department": "Sales", "depth": 1},
        {"emp_id": 4, "name": "David", "manager_id": 2, "department": "Engineering", "depth": 2},
        {"emp_id": 5, "name": "Eve", "manager_id": 2, "department": "Engineering", "depth": 2},
        {"emp_id": 6, "name": "Frank", "manager_id": 3, "department": "Sales", "depth": 2},
        {"emp_id": 7, "name": "Grace", "manager_id": 6, "department": "Sales", "depth": 3},
        {"emp_id": 8, "name": "Heidi", "manager_id": 1, "department": "HR", "depth": 1}
    ]

    assert isinstance(data, list), "Output JSON must be a list of objects."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(data)}."

    # The requirement specifically mentions it should be sorted by emp_id in ascending order
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}. Expected: {expected}, Actual: {actual}"


def test_script_against_changed_database():
    departments = [
        (91, "Strategy Lab"),
        (92, "Platform Works"),
        (93, "Field Operations"),
    ]
    employees = [
        (105, "Xavier", 7, 93),
        (42, "Zara", None, 91),
        (2, "Willow", 42, 93),
        (88, "Victor", 2, 92),
        (7, "Yasmin", 42, 92),
    ]

    os.remove(DB_PATH)
    with sqlite3.connect(DB_PATH) as conn:
        conn.executescript("""
            CREATE TABLE departments (
                dept_id INTEGER PRIMARY KEY,
                dept_name TEXT
            );
            CREATE TABLE employees (
                emp_id INTEGER PRIMARY KEY,
                name TEXT,
                manager_id INTEGER,
                dept_id INTEGER
            );
        """)
        conn.executemany("INSERT INTO departments VALUES (?, ?)", departments)
        conn.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", employees)

    dept_names = dict(departments)
    by_manager = {}
    roots = []
    for emp_id, name, manager_id, dept_id in employees:
        by_manager.setdefault(manager_id, []).append(emp_id)
        if manager_id is None:
            roots.append(emp_id)

    depths = {}
    pending = [(emp_id, 0) for emp_id in roots]
    while pending:
        emp_id, depth = pending.pop(0)
        depths[emp_id] = depth
        pending.extend((child, depth + 1) for child in by_manager.get(emp_id, []))

    expected = []
    for emp_id, name, manager_id, dept_id in sorted(employees):
        expected.append({
            "emp_id": emp_id,
            "name": name,
            "manager_id": manager_id,
            "department": dept_names[dept_id],
            "depth": depths[emp_id],
        })

    before = database_snapshot()
    run_submission()
    after = database_snapshot()
    assert after == before, "The submission modified the changed database schema or data"

    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        actual = json.load(f)
    assert actual == expected, (
        "Output was not correctly regenerated from the changed database using the hierarchy"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
