#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess
from collections import Counter

import pytest

HOME = "/home/user"
SCRIPT = f"{HOME}/run_analysis.sh"
DB = f"{HOME}/company.db"
OUTPUT = f"{HOME}/cross_dept_analysis.json"
CSV_PATHS = {
    "employees": f"{HOME}/employees.csv",
    "departments": f"{HOME}/departments.csv",
    "projects": f"{HOME}/projects.csv",
    "assignments": f"{HOME}/assignments.csv",
}

BASELINE = {
    "employees": [
        ["id", "name", "manager_id", "dept_id"],
        ["1", "Alice", "", "1"],
        ["2", "Bob", "1", "2"],
        ["3", "Charlie", "2", "2"],
        ["4", "Dave", "2", "3"],
        ["5", "Eve", "3", "2"],
        ["6", "Frank", "4", "3"],
    ],
    "departments": [
        ["id", "name"],
        ["1", "Exec"],
        ["2", "Engineering"],
        ["3", "Sales"],
    ],
    "projects": [
        ["id", "name", "dept_id"],
        ["101", "Alpha", "2"],
        ["102", "Beta", "3"],
        ["103", "Gamma", "1"],
    ],
    "assignments": [
        ["emp_id", "project_id"],
        ["2", "101"],
        ["3", "102"],
        ["4", "101"],
        ["5", "101"],
        ["6", "102"],
        ["2", "103"],
    ],
}

BASELINE_EXPECTED = [
    {
        "employee": "Bob",
        "employee_dept": "Engineering",
        "project": "Gamma",
        "project_dept": "Exec",
        "management_depth": 1,
    },
    {
        "employee": "Charlie",
        "employee_dept": "Engineering",
        "project": "Beta",
        "project_dept": "Sales",
        "management_depth": 2,
    },
    {
        "employee": "Dave",
        "employee_dept": "Sales",
        "project": "Alpha",
        "project_dept": "Engineering",
        "management_depth": 2,
    },
]


def write_fixture(fixture):
    for table, rows in fixture.items():
        with open(CSV_PATHS[table], "w", newline="") as f:
            csv.writer(f, lineterminator="\n").writerows(rows)


def run_script():
    for path in (DB, OUTPUT):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def load_json():
    assert os.path.isfile(OUTPUT), f"JSON output {OUTPUT} does not exist."
    with open(OUTPUT, encoding="utf-8") as f:
        try:
            return json.load(
                f,
                parse_constant=lambda value: (_ for _ in ()).throw(
                    ValueError(f"non-standard JSON value {value}")
                ),
            )
        except (json.JSONDecodeError, ValueError) as exc:
            pytest.fail(f"File {OUTPUT} does not contain strict valid JSON: {exc}")


def assert_json(data, expected):
    assert isinstance(data, list), "JSON output should be a list of objects."
    assert len(data) == len(expected), (
        f"Expected {len(expected)} records, but got {len(data)}."
    )
    required = {
        "employee",
        "employee_dept",
        "project",
        "project_dept",
        "management_depth",
    }
    for row in data:
        assert isinstance(row, dict), "Every JSON array element must be an object."
        assert set(row) == required, f"JSON object has incorrect keys: {row}"
        for key in required - {"management_depth"}:
            assert type(row[key]) is str, f"{key} must be a string."
        assert type(row["management_depth"]) is int, "management_depth must be an integer."
    assert data == sorted(data, key=lambda row: (row["employee"], row["project"])), (
        "Results are not sorted by employee and then project."
    )
    assert data == expected, (
        f"JSON output does not match the expected cross-departmental analysis.\n"
        f"Expected: {expected}\nGot: {data}"
    )


def normalize(value):
    return None if value is None else str(value)


def assert_database(fixture):
    assert os.path.isfile(DB), f"Database {DB} does not exist."
    try:
        conn = sqlite3.connect(DB)
        assert conn.execute("PRAGMA integrity_check").fetchone() == ("ok",), (
            "Database integrity check failed."
        )

        actual_tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        assert set(fixture).issubset(actual_tables), (
            f"Database is missing required imported tables: {set(fixture) - actual_tables}"
        )

        for table, csv_rows in fixture.items():
            expected_header = csv_rows[0]
            info = conn.execute(f'PRAGMA table_info("{table}")').fetchall()
            columns = [row[1] for row in info]
            assert columns == expected_header, (
                f"Table {table} has columns {columns}, expected {expected_header}."
            )
            selected = ", ".join(f'"{column}"' for column in expected_header)
            actual_rows = [
                tuple(normalize(value) for value in row)
                for row in conn.execute(f'SELECT {selected} FROM "{table}"')
            ]
            expected_rows = [
                tuple(None if value == "" else value for value in row)
                for row in csv_rows[1:]
            ]
            assert Counter(actual_rows) == Counter(expected_rows), (
                f"Table {table} does not contain exactly the imported CSV data.\n"
                f"Expected: {expected_rows}\nGot: {actual_rows}"
            )

        indexed_columns = set()
        user_index_count = 0
        for table in fixture:
            for index_row in conn.execute(f'PRAGMA index_list("{table}")'):
                index_name = index_row[1]
                origin = index_row[3] if len(index_row) > 3 else "c"
                if origin != "c":
                    continue
                user_index_count += 1
                escaped = index_name.replace('"', '""')
                for column_row in conn.execute(f'PRAGMA index_info("{escaped}")'):
                    if column_row[2] is not None:
                        indexed_columns.add((table, column_row[2]))

        assert user_index_count >= 3, "Expected multiple explicit indexes for joins and lookups."
        assert ("employees", "manager_id") in indexed_columns, (
            "employees.manager_id must be indexed for recursive hierarchy lookup."
        )
        assert (
            ("assignments", "emp_id") in indexed_columns
            or ("assignments", "project_id") in indexed_columns
        ), "Assignments join columns are not indexed."
        assert (
            ("employees", "dept_id") in indexed_columns
            or ("projects", "dept_id") in indexed_columns
        ), "Department join columns are not indexed."
    except sqlite3.Error as exc:
        pytest.fail(f"Failed to validate SQLite database {DB}: {exc}")
    finally:
        if "conn" in locals():
            conn.close()


def derive_expected(fixture):
    employees = {
        row[0]: {"name": row[1], "manager_id": row[2], "dept_id": row[3]}
        for row in fixture["employees"][1:]
    }
    departments = {row[0]: row[1] for row in fixture["departments"][1:]}
    projects = {
        row[0]: {"name": row[1], "dept_id": row[2]}
        for row in fixture["projects"][1:]
    }

    depths = {}

    def depth(employee_id, active=None):
        if employee_id in depths:
            return depths[employee_id]
        active = set() if active is None else active
        assert employee_id not in active, "Verifier fixture contains a management cycle."
        manager_id = employees[employee_id]["manager_id"]
        value = 0 if manager_id == "" else depth(manager_id, active | {employee_id}) + 1
        depths[employee_id] = value
        return value

    result = []
    for emp_id, project_id in fixture["assignments"][1:]:
        employee = employees[emp_id]
        project = projects[project_id]
        if employee["dept_id"] != project["dept_id"]:
            result.append(
                {
                    "employee": employee["name"],
                    "employee_dept": departments[employee["dept_id"]],
                    "project": project["name"],
                    "project_dept": departments[project["dept_id"]],
                    "management_depth": depth(emp_id),
                }
            )
    return sorted(result, key=lambda row: (row["employee"], row["project"]))


def dynamic_fixture():
    suffix = secrets.token_hex(6)
    return {
        "employees": [
            ["id", "name", "manager_id", "dept_id"],
            ["901", f"Root-{suffix}", "", "17"],
            ["37", f"Zara-{suffix}", "901", "42"],
            ["555", f"Milo-{suffix}", "37", "88"],
            ["12", f"Bea-{suffix}", "555", "42"],
            ["808", f"Quinn-{suffix}", "12", "88"],
            ["77", f"Ada-{suffix}", "37", "42"],
        ],
        "departments": [
            ["id", "name"],
            ["17", f"Executive-{suffix}"],
            ["42", f"Research-{suffix}"],
            ["88", f"Operations-{suffix}"],
        ],
        "projects": [
            ["id", "name", "dept_id"],
            ["300", f"Nebula-{suffix}", "42"],
            ["301", f"Atlas-{suffix}", "88"],
            ["302", f"Core-{suffix}", "17"],
            ["303", f"Zephyr-{suffix}", "42"],
        ],
        "assignments": [
            ["emp_id", "project_id"],
            ["901", "302"],
            ["37", "300"],
            ["37", "302"],
            ["37", "301"],
            ["555", "300"],
            ["12", "301"],
            ["808", "302"],
            ["77", "301"],
            ["77", "303"],
        ],
    }


def test_complete_analysis():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    mode = os.stat(SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, encoding="utf-8", errors="replace") as f:
        script_text = f.read()
    uncommented = re.sub(r"(?m)^\s*#.*$", "", script_text)
    uncommented = re.sub(r"(?m)--.*$", "", uncommented)
    assert re.search(r"\bWITH\s+RECURSIVE\b", uncommented, re.IGNORECASE), (
        "run_analysis.sh does not contain the required recursive SQL CTE."
    )

    write_fixture(BASELINE)
    run_script()
    assert_database(BASELINE)
    assert_json(load_json(), BASELINE_EXPECTED)

    fixture = dynamic_fixture()
    expected = derive_expected(fixture)
    write_fixture(fixture)
    run_script()
    assert_database(fixture)
    assert_json(load_json(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
