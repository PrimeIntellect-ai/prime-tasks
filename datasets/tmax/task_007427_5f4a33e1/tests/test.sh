#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import sqlite3
import stat
import subprocess
from pathlib import Path

import pytest

DB_PATH = Path("/home/user/company.db")
SCRIPT_PATH = Path("/home/user/etl.py")
CSV_PATH = Path("/home/user/manager_project_hours.csv")


def remove_db_sidecars():
    for suffix in ("-wal", "-shm", "-journal"):
        Path(str(DB_PATH) + suffix).unlink(missing_ok=True)


def run_etl():
    CSV_PATH.unlink(missing_ok=True)
    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"etl.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def read_csv():
    assert CSV_PATH.exists(), f"Output file {CSV_PATH} does not exist."
    assert CSV_PATH.is_file(), f"{CSV_PATH} is not a regular file."
    with CSV_PATH.open("r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")
        return header, list(reader)


@pytest.fixture(scope="module")
def original_run():
    assert SCRIPT_PATH.exists(), f"Required script {SCRIPT_PATH} does not exist."
    assert not SCRIPT_PATH.is_symlink(), f"{SCRIPT_PATH} must be a regular Python file, not a symlink."
    mode = SCRIPT_PATH.stat().st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} is not a regular file."
    assert DB_PATH.is_file(), f"Database {DB_PATH} does not exist."

    original_db = DB_PATH.read_bytes()
    try:
        run_etl()
        yield
    finally:
        remove_db_sidecars()
        DB_PATH.write_bytes(original_db)


def test_output_csv_exists(original_run):
    csv_path = "/home/user/manager_project_hours.csv"
    assert os.path.exists(csv_path), f"Output file {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"{csv_path} is not a regular file."


def test_output_csv_content(original_run):
    csv_path = "/home/user/manager_project_hours.csv"
    assert os.path.exists(csv_path), "Cannot check content because CSV file is missing."

    expected_rows = [
        ["Alice", "Alpha", "45"],
        ["Alice", "Beta", "35"],
        ["Bob", "Alpha", "30"],
        ["Bob", "Beta", "15"],
        ["Charlie", "Alpha", "5"],
        ["Charlie", "Beta", "20"]
    ]
    expected_header = ["manager_name", "project_name", "total_hours"]

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        assert header == expected_header, f"Expected header {expected_header}, but got {header}."

        actual_rows = list(reader)
        assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

        for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
            assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."


def build_random_database():
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 100000), 9)

    def unique_labels(prefix, count):
        labels = set()
        while len(labels) < count:
            labels.add(f"{prefix}_{rng.randrange(10**8, 10**9)}")
        return list(labels)

    employee_names = unique_labels("Employee", 9)
    project_names = unique_labels("Project", 4)

    # This tree contains multiple managers and a four-level downline.
    parent_indexes = [None, 0, 0, 1, 3, 2, 2, 6, 0]
    employees = [
        (ids[i], employee_names[i], None if parent is None else ids[parent])
        for i, parent in enumerate(parent_indexes)
    ]
    project_ids = rng.sample(range(100000, 200000), 4)
    projects = [(project_ids[i], project_names[i]) for i in range(4)]

    hours = [rng.randrange(2, 30) for _ in range(12)]
    timesheets = [
        (ids[0], project_ids[0], hours[0]),
        (ids[1], project_ids[1], hours[1]),
        (ids[2], project_ids[2], hours[2]),
        (ids[3], project_ids[3], hours[3]),
        (ids[4], project_ids[0], hours[4]),
        (ids[5], project_ids[1], hours[5]),
        (ids[6], project_ids[2], hours[6]),
        (ids[7], project_ids[3], hours[7]),
        (ids[8], project_ids[1], hours[8]),
        # Duplicate entries ensure aggregation is not just one row per pair.
        (ids[4], project_ids[0], hours[9]),
        (ids[7], project_ids[3], hours[10]),
        (ids[1], project_ids[1], hours[11]),
        # Zero and NULL entries must not create output rows by themselves.
        (ids[5], project_ids[3], 0),
        (ids[8], project_ids[2], None),
    ]

    remove_db_sidecars()
    DB_PATH.unlink(missing_ok=True)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)")
        conn.execute("CREATE TABLE projects (project_id INTEGER PRIMARY KEY, project_name TEXT)")
        conn.execute("CREATE TABLE timesheets (emp_id INTEGER, project_id INTEGER, hours INTEGER)")
        conn.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)
        conn.executemany("INSERT INTO projects VALUES (?, ?)", projects)
        conn.executemany("INSERT INTO timesheets VALUES (?, ?, ?)", timesheets)
        conn.commit()
    finally:
        conn.close()

    return employees, projects, timesheets


def derive_expected(employees, projects, timesheets):
    names = {emp_id: name for emp_id, name, _ in employees}
    children = {emp_id: [] for emp_id, _, _ in employees}
    manager_ids = set()
    for emp_id, _, manager_id in employees:
        if manager_id is not None:
            manager_ids.add(manager_id)
            children.setdefault(manager_id, []).append(emp_id)

    project_names = {project_id: name for project_id, name in projects}
    expected = []
    for manager_id in manager_ids:
        downline = set()
        pending = [manager_id]
        while pending:
            emp_id = pending.pop()
            if emp_id in downline:
                continue
            downline.add(emp_id)
            pending.extend(children.get(emp_id, []))

        totals = {}
        for emp_id, project_id, hours in timesheets:
            if emp_id in downline and project_id in project_names and hours is not None:
                totals[project_id] = totals.get(project_id, 0) + hours

        for project_id, total in totals.items():
            if total != 0:
                expected.append([names[manager_id], project_names[project_id], str(total)])

    expected.sort(key=lambda row: (row[0], row[1]))
    return expected


def test_etl_against_randomized_database(original_run):
    employees, projects, timesheets = build_random_database()
    expected_rows = derive_expected(employees, projects, timesheets)

    run_etl()
    header, actual_rows = read_csv()

    expected_header = ["manager_name", "project_name", "total_hours"]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}."
    assert actual_rows == expected_rows, (
        "ETL output did not match the recursively derived manager/project totals "
        "for the randomized database."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
