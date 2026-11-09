#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import sqlite3
import subprocess
import sys

import pytest

DB_PATH = '/home/user/company.db'
EXTRACT_PATH = '/home/user/extract.py'
ANALYZE_PATH = '/home/user/analyze.py'
JSON_PATH = '/home/user/graph_data.json'
CSV_PATH = '/home/user/cross_dept_collabs.csv'


def expected_json_data():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT e.id, e.dept_id, p.id
        FROM employees e
        JOIN departments d ON d.id = e.dept_id
        LEFT JOIN employee_projects ep ON ep.emp_id = e.id
        LEFT JOIN projects p ON p.id = ep.proj_id
        ORDER BY e.id, p.id
    """)
    rows = cursor.fetchall()
    conn.close()

    expected = {}
    for employee_id, department_id, project_id in rows:
        item = expected.setdefault(employee_id, {
            'department_id': department_id,
            'projects': set(),
        })
        assert item['department_id'] == department_id
        if project_id is not None:
            item['projects'].add(project_id)
    return expected


def assert_json_is_complete_and_correct():
    assert os.path.exists(JSON_PATH), f"JSON file not found at {JSON_PATH}"
    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("graph_data.json is not a valid JSON file.")

    assert isinstance(data, list), "JSON root must be a list."
    expected = expected_json_data()
    actual = {}

    for item in data:
        assert isinstance(item, dict), "Every JSON list item must be an object."
        assert set(item) == {'employee_id', 'department_id', 'projects'}, \
            "Each JSON object must contain exactly employee_id, department_id, and projects."
        assert type(item['employee_id']) is int, "employee_id must be an integer."
        assert type(item['department_id']) is int, "department_id must be an integer."
        assert isinstance(item['projects'], list), "'projects' must be a list."
        assert all(type(project_id) is int for project_id in item['projects']), \
            "Every project ID must be an integer."
        assert len(item['projects']) == len(set(item['projects'])), \
            "An employee's projects must not contain duplicate IDs."
        assert item['employee_id'] not in actual, "Each employee must appear exactly once."
        actual[item['employee_id']] = {
            'department_id': item['department_id'],
            'projects': set(item['projects']),
        }

    assert actual == expected, \
        "graph_data.json does not contain the complete employee, department, and project mapping."


@pytest.fixture(scope='session', autouse=True)
def run_pipeline():
    for path in (EXTRACT_PATH, ANALYZE_PATH):
        assert os.path.exists(path), f"Required script not found at {path}"
        assert os.path.isfile(path), f"Required script is not a regular file: {path}"

    for path in (JSON_PATH, CSV_PATH):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        [sys.executable, EXTRACT_PATH],
        cwd='/home/user', capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, \
        f"extract.py failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(JSON_PATH), "extract.py did not create graph_data.json."
    assert_json_is_complete_and_correct()

    result = subprocess.run(
        [sys.executable, ANALYZE_PATH],
        cwd='/home/user', capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, \
        f"analyze.py failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(CSV_PATH), "analyze.py did not create cross_dept_collabs.csv."


def test_indexes_created():
    """Check if indexes were added to the database to optimize queries."""
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'")
    indexes = cursor.fetchall()
    conn.close()

    assert len(indexes) > 0, "No custom indexes found in the database. You need to add indexes to optimize query performance."
    indexed_tables = {row[1] for row in indexes}
    assert 'employee_projects' in indexed_tables or 'employees' in indexed_tables, \
        "Expected indexes on employee_projects or employees tables."


def test_json_output_format():
    """Check the complete graph_data.json document and its database mapping."""
    assert_json_is_complete_and_correct()


def test_csv_output_correctness():
    """Check if cross_dept_collabs.csv contains the exact unique, sorted pairs."""
    assert os.path.exists(CSV_PATH), f"CSV file not found at {CSV_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT DISTINCT e1.id AS emp1_id,
                        e2.id AS emp2_id,
                        ep1.proj_id AS shared_project_id
        FROM employees e1
        JOIN employee_projects ep1 ON e1.id = ep1.emp_id
        JOIN projects p ON p.id = ep1.proj_id
        JOIN employee_projects ep2 ON ep1.proj_id = ep2.proj_id
        JOIN employees e2 ON ep2.emp_id = e2.id
        WHERE e1.id < e2.id AND e1.dept_id != e2.dept_id
        ORDER BY e1.id ASC, e2.id ASC, ep1.proj_id ASC
    """)
    expected_rows = cursor.fetchall()
    conn.close()
    expected_data = [(str(a), str(b), str(p)) for a, b, p in expected_rows]

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == ['emp1_id', 'emp2_id', 'shared_project_id'], \
            "CSV headers are incorrect."
        actual_data = []
        for row in reader:
            assert len(row) == 3, "Every CSV data row must contain exactly three fields."
            actual_data.append(tuple(row))

    assert len(actual_data) == len(set(actual_data)), \
        "cross_dept_collabs.csv contains duplicate collaboration triples."
    assert actual_data == expected_data, \
        "The data in cross_dept_collabs.csv does not match the expected unique, sorted output based on the database."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
