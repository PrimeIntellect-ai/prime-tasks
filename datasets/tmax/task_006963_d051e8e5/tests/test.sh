#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
import stat
import subprocess
import uuid

import pytest

ETL_DIR = "/home/user/etl"
SOURCE = os.path.join(ETL_DIR, "pipeline.cpp")
REPORT = os.path.join(ETL_DIR, "final_report.csv")
DATABASE = "/home/user/data/company.db"
EXECUTABLE = "/tmp/submission_pipeline"

SCHEMA = """
CREATE TABLE departments (
    id INTEGER PRIMARY KEY,
    name TEXT
);
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER,
    dept_id INTEGER,
    salary INTEGER,
    hire_date DATE
);
"""

ORIGINAL_DEPARTMENTS = [(1, "Engineering"), (2, "Sales")]
ORIGINAL_EMPLOYEES = [
    (1, "Alice", None, 1, 150000, "2020-01-15"),
    (2, "Bob", 1, 1, 120000, "2020-03-01"),
    (3, "Charlie", 1, 1, 110000, "2020-05-20"),
    (4, "Diana", None, 2, 130000, "2019-11-10"),
    (5, "Evan", 4, 2, 90000, "2021-02-15"),
    (6, "Fiona", 2, 1, 95000, "2021-06-01"),
]

EXPECTED_HEADER = [
    "emp_id", "emp_name", "dept_name", "management_level", "salary",
    "dept_running_total"
]
EXPECTED_ORIGINAL_ROWS = [
    ["1", "Alice", "Engineering", "1", "150000", "150000"],
    ["2", "Bob", "Engineering", "2", "120000", "270000"],
    ["3", "Charlie", "Engineering", "2", "110000", "380000"],
    ["6", "Fiona", "Engineering", "3", "95000", "475000"],
    ["4", "Diana", "Sales", "1", "130000", "130000"],
    ["5", "Evan", "Sales", "2", "90000", "220000"],
]


def create_database(departments, employees):
    for path in (DATABASE, DATABASE + "-wal", DATABASE + "-shm", DATABASE + "-journal"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DATABASE)
    conn.executescript(SCHEMA)
    conn.executemany("INSERT INTO departments(id, name) VALUES (?, ?)", departments)
    conn.executemany(
        "INSERT INTO employees(id, name, manager_id, dept_id, salary, hire_date) "
        "VALUES (?, ?, ?, ?, ?, ?)", employees
    )
    conn.commit()
    conn.close()


def run_pipeline():
    try:
        os.remove(REPORT)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [EXECUTABLE], cwd=ETL_DIR, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Compiled pipeline exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_report():
    assert os.path.isfile(REPORT), "The file /home/user/etl/final_report.csv is missing."
    with open(REPORT, "r", encoding="utf-8", newline="") as handle:
        return list(csv.reader(handle))


def expected_rows(departments, employees):
    dept_names = dict(departments)
    by_id = {employee[0]: employee for employee in employees}
    levels = {}

    def level(emp_id, visiting=None):
        if emp_id in levels:
            return levels[emp_id]
        if visiting is None:
            visiting = set()
        assert emp_id not in visiting, "Verifier fixture unexpectedly contains a manager cycle"
        visiting.add(emp_id)
        manager_id = by_id[emp_id][2]
        value = 1 if manager_id is None else level(manager_id, visiting) + 1
        visiting.remove(emp_id)
        levels[emp_id] = value
        return value

    ordered = sorted(employees, key=lambda employee: (dept_names[employee[3]], employee[5]))
    totals = {}
    rows = []
    for emp_id, name, manager_id, dept_id, salary, hire_date in ordered:
        totals[dept_id] = totals.get(dept_id, 0) + salary
        rows.append([
            str(emp_id), name, dept_names[dept_id], str(level(emp_id)),
            str(salary), str(totals[dept_id])
        ])
    return rows


def assert_staging_matches(departments, employees):
    dept_names = dict(departments)
    expected = sorted([
        (emp_id, name, dept_names[dept_id], manager_id, salary, hire_date)
        for emp_id, name, manager_id, dept_id, salary, hire_date in employees
    ])

    conn = sqlite3.connect(DATABASE)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='stg_emp_dept'")
    assert cursor.fetchone() is not None, "The 'stg_emp_dept' table is missing from the database."
    cursor.execute("SELECT COUNT(*) FROM stg_emp_dept")
    count = cursor.fetchone()[0]
    cursor.execute(
        "SELECT emp_id, emp_name, dept_name, manager_id, salary, hire_date "
        "FROM stg_emp_dept ORDER BY emp_id"
    )
    actual = cursor.fetchall()
    conn.close()

    assert count == len(employees), (
        f"The 'stg_emp_dept' table should have {len(employees)} rows, but found {count}. "
        "The cartesian product bug might not be fixed."
    )
    assert actual == expected, "stg_emp_dept does not correctly map employees to departments."


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_original_fixture():
    assert os.path.exists(SOURCE), "The required source file /home/user/etl/pipeline.cpp is missing."
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), "pipeline.cpp must be a regular source file."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as handle:
        source_text = handle.read()
    without_comments = re.sub(r"//.*?$|/[*].*?[*]/", "", source_text, flags=re.MULTILINE | re.DOTALL)
    assert re.search(r"WITH[ \"()+]*RECURSIVE", without_comments, re.IGNORECASE), (
        "pipeline.cpp must implement management levels with a recursive CTE."
    )
    assert re.search(r"OVER[ \"()+]*[(]", without_comments, re.IGNORECASE), (
        "pipeline.cpp must implement the department running total with a window function."
    )

    build = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-lsqlite3", "-o", EXECUTABLE],
        cwd=ETL_DIR, text=True, capture_output=True, timeout=30
    )
    assert build.returncode == 0, (
        f"pipeline.cpp did not compile successfully.\nstdout:\n{build.stdout}\n"
        f"stderr:\n{build.stderr}"
    )
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)
    with open(EXECUTABLE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Compilation did not produce a native executable."

    create_database(ORIGINAL_DEPARTMENTS, ORIGINAL_EMPLOYEES)
    run_pipeline()


def test_final_report_exists():
    assert os.path.isfile(REPORT), "The file /home/user/etl/final_report.csv is missing."


def test_staging_table_fixed():
    assert os.path.isfile(DATABASE), f"The database file {DATABASE} is missing."
    assert_staging_matches(ORIGINAL_DEPARTMENTS, ORIGINAL_EMPLOYEES)


def test_final_report_content():
    rows = read_report()
    assert len(rows) > 0, "The file final_report.csv is empty."
    assert rows[0] == EXPECTED_HEADER, f"Expected header {EXPECTED_HEADER}, but got {rows[0]}."
    data_rows = rows[1:]
    assert len(data_rows) == len(EXPECTED_ORIGINAL_ROWS), (
        f"Expected {len(EXPECTED_ORIGINAL_ROWS)} data rows, but got {len(data_rows)}."
    )
    for index, (actual, expected) in enumerate(zip(data_rows, EXPECTED_ORIGINAL_ROWS)):
        assert actual == expected, f"Row {index + 1} mismatch: expected {expected}, got {actual}."


def test_pipeline_on_unseen_input():
    token = uuid.uuid4().hex[:10]
    departments = [
        (31, "Analytics_" + token),
        (7, "Operations_" + token),
        (90, "Research_" + token),
    ]
    base = int(token[:5], 16) % 10000
    employees = [
        (101, "RootA_" + token, None, 31, 201000 + base, "2018-01-03"),
        (205, "ChildA_" + token, 101, 31, 83000 + base, "2019-04-12"),
        (309, "GrandA_" + token, 205, 31, 92000 + base, "2020-07-21"),
        (412, "DeepA_" + token, 309, 31, 77000 + base, "2022-09-09"),
        (518, "RootO_" + token, None, 7, 188000 + base, "2017-02-14"),
        (623, "ChildO_" + token, 518, 7, 99000 + base, "2019-11-30"),
        (734, "PeerO_" + token, 518, 7, 105000 + base, "2021-05-18"),
        (845, "RootR_" + token, None, 90, 175000 + base, "2016-08-08"),
        (956, "ChildR_" + token, 845, 90, 88000 + base, "2023-03-27"),
    ]

    create_database(departments, employees)
    run_pipeline()
    assert_staging_matches(departments, employees)

    rows = read_report()
    assert rows, "The regenerated final_report.csv is empty."
    assert rows[0] == EXPECTED_HEADER, f"Expected header {EXPECTED_HEADER}, but got {rows[0]}."
    assert rows[1:] == expected_rows(departments, employees), (
        "The pipeline produced incorrect hierarchy levels, department running totals, "
        "department joins, or output ordering for an unseen database."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
