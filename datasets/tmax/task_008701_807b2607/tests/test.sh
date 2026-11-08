#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_tracked_script.py
import os
import re
import runpy
import sqlite3

trace_path = os.environ["SQL_TRACE_PATH"]
original_connect = sqlite3.connect

def tracked_connect(*args, **kwargs):
    conn = original_connect(*args, **kwargs)
    def trace(sql):
        if re.search(r"\bREINDEX\b", sql, re.IGNORECASE):
            with open(trace_path, "a", encoding="utf-8") as f:
                f.write(sql + "\n")
    conn.set_trace_callback(trace)
    return conn

sqlite3.connect = tracked_connect
runpy.run_path("/home/user/process_salaries.py", run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import secrets
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/company.db"
SCRIPT_PATH = "/home/user/process_salaries.py"
CSV_PATH = "/home/user/department_summary.csv"
TRACE_PATH = "/tmp/process_salaries_sql_trace.txt"
RUNNER_PATH = "/tmp/run_tracked_script.py"

def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

def test_csv_exists():
    assert os.path.exists(CSV_PATH), f"CSV file missing at {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file"

def test_csv_content():
    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 1, "CSV file is empty"

    header = rows[0]
    assert header == ['department_name', 'total_salary'], f"Incorrect CSV header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows in CSV, found {len(data_rows)}"

    expected_data = {
        'Engineering': 230000,
        'Sales': 175000,
        'Marketing': 75000
    }

    actual_data = {}
    for row in data_rows:
        assert len(row) == 2, f"Expected 2 columns in row, found {len(row)}: {row}"
        dept, salary_str = row
        try:
            salary = int(salary_str)
        except ValueError:
            pytest.fail(f"Salary for {dept} is not a valid integer: {salary_str}")
        actual_data[dept] = salary

    assert actual_data == expected_data, f"CSV data mismatch. Expected {expected_data}, got {actual_data}"

def test_db_integrity():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA integrity_check;")
    result = cursor.fetchone()
    conn.close()
    assert result and result[0] == "ok", "Database integrity check failed"

def test_script_executes_reindex_and_derives_fresh_valid_output():
    token = secrets.token_hex(12)
    valid_departments = [f"Dynamic_{token}_{i}" for i in range(3)]
    salary_groups = [
        [secrets.randbelow(40000) + 10001, secrets.randbelow(40000) + 10001],
        [secrets.randbelow(40000) + 10001],
        [secrets.randbelow(40000) + 10001, secrets.randbelow(40000) + 10001,
         secrets.randbelow(40000) + 10001],
    ]
    expected = {
        name: sum(salaries)
        for name, salaries in zip(valid_departments, salary_groups)
    }

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM employees")
        conn.execute("DELETE FROM departments")

        emp_id = 1
        for dept_id, (name, salaries) in enumerate(zip(valid_departments, salary_groups), 1):
            conn.execute(
                "INSERT INTO departments(dept_id, department_name) VALUES (?, ?)",
                (dept_id, name),
            )
            for salary in salaries:
                conn.execute(
                    "INSERT INTO employees(emp_id, emp_name, dept_id, salary) VALUES (?, ?, ?, ?)",
                    (emp_id, f"Employee_{token}_{emp_id}", dept_id, salary),
                )
                emp_id += 1

        # These groups exercise both required validation branches and must not be exported.
        conn.execute("INSERT INTO departments(dept_id, department_name) VALUES (100, '')")
        conn.execute(
            "INSERT INTO employees(emp_id, emp_name, dept_id, salary) VALUES (?, ?, 100, ?)",
            (emp_id, "EmptyName", 12345),
        )
        emp_id += 1
        conn.execute(
            "INSERT INTO departments(dept_id, department_name) VALUES (?, ?)",
            (101, sqlite3.Binary(b"not-a-string")),
        )
        conn.execute(
            "INSERT INTO employees(emp_id, emp_name, dept_id, salary) VALUES (?, ?, 101, ?)",
            (emp_id, "BlobName", 23456),
        )
        emp_id += 1
        conn.execute(
            "INSERT INTO departments(dept_id, department_name) VALUES (102, ?)",
            (f"NonInteger_{token}",),
        )
        conn.execute(
            "INSERT INTO employees(emp_id, emp_name, dept_id, salary) VALUES (?, ?, 102, ?)",
            (emp_id, "FractionalSalary", 123.5),
        )
        conn.commit()
    finally:
        conn.close()

    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    if os.path.exists(TRACE_PATH):
        os.unlink(TRACE_PATH)

    env = os.environ.copy()
    env["SQL_TRACE_PATH"] = TRACE_PATH
    result = subprocess.run(
        ["python3", RUNNER_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_salaries.py failed when executed. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(CSV_PATH), "Executing the script did not create the CSV"
    assert os.path.isfile(TRACE_PATH), "The script did not execute a REINDEX command"
    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        traced_sql = f.read()
    assert re.search(r"\bREINDEX\b", traced_sql, re.IGNORECASE), (
        "The script did not execute the required SQLite REINDEX command"
    )

    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["department_name", "total_salary"], (
        f"Incorrect CSV header after execution: {rows[0] if rows else None}"
    )

    actual = {}
    for row in rows[1:]:
        assert len(row) == 2, f"Expected exactly two columns, got: {row}"
        name, salary_text = row
        assert name, "Exported department_name must be non-empty"
        try:
            salary = int(salary_text)
        except ValueError:
            pytest.fail(f"Exported total_salary is not an integer: {salary_text!r}")
        assert name not in actual, f"Duplicate department in output: {name}"
        actual[name] = salary
    assert actual == expected, f"Fresh execution produced {actual}, expected {expected}"

    conn = sqlite3.connect(DB_PATH)
    try:
        index_row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_emp_dept'"
        ).fetchone()
        integrity = conn.execute("PRAGMA integrity_check").fetchone()
    finally:
        conn.close()
    assert index_row == ("idx_emp_dept",), "Required employee department index is missing"
    assert integrity and integrity[0] == "ok", "Database failed integrity check after script execution"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
