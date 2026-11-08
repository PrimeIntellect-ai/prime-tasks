#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

APP_DIR = "/home/user/app"
DB_PATH = os.path.join(APP_DIR, "company.db")
RESULTS_PATH = os.path.join(APP_DIR, "results.json")
PLAN_PATH = os.path.join(APP_DIR, "plan.txt")
BINARY_PATH = "/tmp/company-app-verifier"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load_results():
    require(os.path.exists(RESULTS_PATH), f"File {RESULTS_PATH} does not exist.")
    try:
        with open(RESULTS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {RESULTS_PATH} does not contain valid JSON: {exc}")

    require(isinstance(data, list), "results.json must contain a JSON array.")
    for i, item in enumerate(data):
        require(isinstance(item, dict), f"Result entry {i} is not an object.")
        require(set(item.keys()) == {"employee_name", "project_name"},
                f"Result entry {i} does not match the required schema: {item}")
        require(isinstance(item["employee_name"], str),
                f"employee_name in entry {i} is not a string.")
        require(isinstance(item["project_name"], str),
                f"project_name in entry {i} is not a string.")
    return data


def normalized(rows):
    return sorted(rows, key=lambda x: (x["employee_name"], x["project_name"]))


def run_program():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    subprocess.run([BINARY_PATH], cwd=APP_DIR, check=True, timeout=30)
    return load_results()


# Preserve the original Go module assertions.
go_mod_path = os.path.join(APP_DIR, "go.mod")
go_sum_path = os.path.join(APP_DIR, "go.sum")
require(os.path.exists(go_mod_path), f"Go module not initialized, {go_mod_path} is missing.")
require(os.path.exists(go_sum_path), f"Go dependencies not installed, {go_sum_path} is missing.")
with open(go_mod_path, "r", encoding="utf-8") as f:
    require("github.com/mattn/go-sqlite3" in f.read(),
            "go-sqlite3 is not listed in go.mod.")

require(os.path.isfile(os.path.join(APP_DIR, "main.go")), "main.go is missing.")
require(os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist.")

# Preserve the original existence checks, then verify that the indexes actually
# lead with the required columns and are usable non-partial indexes.
with sqlite3.connect(DB_PATH) as conn:
    emp_indexes = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='employees'"
    ).fetchall()
    proj_indexes = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='projects'"
    ).fetchall()
    require(len(emp_indexes) > 0, "No index found on the 'employees' table.")
    require(len(proj_indexes) > 0, "No index found on the 'projects' table.")

    def suitable_indexes(table, required_column):
        suitable = []
        for row in conn.execute(f"PRAGMA index_list('{table}')"):
            name = row[1]
            partial = row[4] if len(row) > 4 else 0
            columns = [r[2] for r in conn.execute(
                "SELECT seqno, cid, name FROM pragma_index_info(?) ORDER BY seqno", (name,)
            )]
            if not partial and columns and columns[0] == required_column:
                suitable.append(name)
        return suitable

    employee_manager_indexes = suitable_indexes("employees", "manager_id")
    project_employee_indexes = suitable_indexes("projects", "employee_id")
    require(employee_manager_indexes,
            "No usable index beginning with employees.manager_id was found.")
    require(project_employee_indexes,
            "No usable index beginning with projects.employee_id was found.")

# Preserve the plan existence and SEARCH/SCAN assertion and require the supplied
# plan to describe a recursive, indexed LEFT JOIN plan.
require(os.path.exists(PLAN_PATH), f"File {PLAN_PATH} does not exist.")
with open(PLAN_PATH, "r", encoding="utf-8") as f:
    plan = f.read()
plan_lower = plan.lower()
require("search" in plan_lower or "scan" in plan_lower,
        f"File {PLAN_PATH} does not appear to contain a valid EXPLAIN QUERY PLAN output (missing SEARCH or SCAN).")
require("query plan" in plan_lower, "plan.txt is missing sqlite3 EXPLAIN QUERY PLAN output.")
require("recursive" in plan_lower and "subordinates" in plan_lower,
        "plan.txt does not show execution of the recursive subordinates CTE.")
require("left-join" in plan_lower,
        "plan.txt does not show the required LEFT JOIN to projects.")
require(any(name.lower() in plan_lower for name in employee_manager_indexes),
        "plan.txt does not show use of an index on employees.manager_id.")
require(any(name.lower() in plan_lower for name in project_employee_indexes),
        "plan.txt does not show use of an index on projects.employee_id.")

# The submitted program must compile; results are generated only by this freshly
# built executable, not trusted from files left by the agent.
subprocess.run(
    ["go", "build", "-o", BINARY_PATH, "main.go"],
    cwd=APP_DIR,
    check=True,
    timeout=120,
    env={**os.environ, "CGO_ENABLED": "1"},
)
require(os.path.isfile(BINARY_PATH) and os.path.getsize(BINARY_PATH) > 0,
        "go build did not produce an executable.")

# Preserve the original fixed-data result assertion, but check freshly generated
# output from the compiled submission.
expected_original = [
    {"employee_name": "Alice", "project_name": ""},
    {"employee_name": "Bob", "project_name": "Project Alpha"},
    {"employee_name": "Charlie", "project_name": "Project Beta"},
    {"employee_name": "Charlie", "project_name": "Project Gamma"},
    {"employee_name": "Dave", "project_name": ""},
]
actual_original = run_program()
require(normalized(actual_original) == normalized(expected_original),
        f"JSON output mismatch. Expected: {normalized(expected_original)} Got: {normalized(actual_original)}")

# Back up the database, replace its records with unpredictable hierarchy/project
# data, run the same binary again, and independently derive the expected answer.
fd, backup_path = tempfile.mkstemp(prefix="company-db-backup-", suffix=".db")
os.close(fd)
try:
    with sqlite3.connect(DB_PATH) as source, sqlite3.connect(backup_path) as backup:
        source.backup(backup)

    token = secrets.token_hex(8)
    employees = [
        (1, f"CEO-{token}", None),
        (11, f"DirectA-{token}", 1),
        (22, f"DirectB-{token}", 1),
        (33, f"Deep-{token}", 11),
        (44, f"Deeper-{token}", 33),
        (99, f"Disconnected-{token}", None),
    ]
    projects = [
        (501, f"A-{token}", 11),
        (502, f"DeepOne-{token}", 33),
        (503, f"DeepTwo-{token}", 33),
        (504, f"Outside-{token}", 99),
    ]

    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("DELETE FROM projects")
        conn.execute("DELETE FROM employees")
        conn.executemany("INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)", employees)
        conn.executemany("INSERT INTO projects(id, name, employee_id) VALUES (?, ?, ?)", projects)
        conn.commit()
        expected_dynamic = [
            {"employee_name": employee_name, "project_name": project_name or ""}
            for employee_name, project_name in conn.execute("""
                WITH RECURSIVE expected_subordinates(id, name, manager_id) AS (
                    SELECT id, name, manager_id FROM employees WHERE id = 1
                    UNION ALL
                    SELECT e.id, e.name, e.manager_id
                    FROM employees AS e
                    JOIN expected_subordinates AS s ON e.manager_id = s.id
                )
                SELECT s.name, p.name
                FROM expected_subordinates AS s
                LEFT JOIN projects AS p ON p.employee_id = s.id
            """)
        ]

    actual_dynamic = run_program()
    require(normalized(actual_dynamic) == normalized(expected_dynamic),
            f"Program failed on verifier-generated data. Expected: {normalized(expected_dynamic)} Got: {normalized(actual_dynamic)}")
finally:
    try:
        with sqlite3.connect(backup_path) as backup, sqlite3.connect(DB_PATH) as destination:
            backup.backup(destination)
    finally:
        if os.path.exists(backup_path):
            os.remove(backup_path)
        if os.path.exists(BINARY_PATH):
            os.remove(BINARY_PATH)

PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
