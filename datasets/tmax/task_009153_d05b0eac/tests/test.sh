#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

REPORT_PATH = '/home/user/compliance_report.json'
SCRIPT_PATH = '/home/user/generate_report.py'
DB_PATH = '/home/user/audit.db'
TRACE_RUNNER = '/tmp/run_report_with_trace.py'
REQUIRED_KEYS = {
    'employee_id',
    'hierarchy_level',
    'top_system',
    'top_system_access_count',
}

TRACE_RUNNER_SOURCE = r'''import runpy
import sqlite3
import sys

script_path = sys.argv[1]
trace_path = sys.argv[2]
statements = []
original_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    connection = original_connect(*args, **kwargs)
    connection.set_trace_callback(statements.append)
    return connection

sqlite3.connect = traced_connect
try:
    runpy.run_path(script_path, run_name='__main__')
finally:
    with open(trace_path, 'w', encoding='utf-8') as trace_file:
        json_module = __import__('json')
        json_module.dump(statements, trace_file)
'''


def get_expected_data():
    """Derives the expected report data directly from the current state of the database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE hierarchy AS (
        SELECT emp_id, 0 AS hierarchy_level
        FROM employees
        WHERE manager_id IS NULL

        UNION ALL

        SELECT e.emp_id, h.hierarchy_level + 1
        FROM employees e
        JOIN hierarchy h ON e.manager_id = h.emp_id
    ),
    system_counts AS (
        SELECT emp_id, system_name, COUNT(*) as access_count
        FROM access_logs
        GROUP BY emp_id, system_name
    ),
    ranked_systems AS (
        SELECT emp_id, system_name, access_count,
               ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY access_count DESC, system_name ASC) as rn
        FROM system_counts
    )
    SELECT h.emp_id as employee_id,
           h.hierarchy_level,
           r.system_name as top_system,
           r.access_count as top_system_access_count
    FROM hierarchy h
    JOIN ranked_systems r ON h.emp_id = r.emp_id AND r.rn = 1
    ORDER BY h.emp_id ASC;
    """

    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return [dict(row) for row in rows]


def run_script_and_get_trace():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} should be a file."

    with open(TRACE_RUNNER, 'w', encoding='utf-8') as runner:
        runner.write(TRACE_RUNNER_SOURCE)

    fd, trace_path = tempfile.mkstemp(prefix='sql_trace_', suffix='.json')
    os.close(fd)
    try:
        result = subprocess.run(
            [sys.executable, TRACE_RUNNER, SCRIPT_PATH, trace_path],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        with open(trace_path, 'r', encoding='utf-8') as trace_file:
            return json.load(trace_file)
    finally:
        if os.path.exists(trace_path):
            os.remove(trace_path)


def assert_required_sql_was_executed(statements):
    candidates = []
    for statement in statements:
        cleaned = re.sub(r'/\*.*?\*/|--[^\n]*', ' ', statement, flags=re.DOTALL)
        cleaned = re.sub(r"'(?:''|[^'])*'", "''", cleaned)
        upper = cleaned.upper()
        if (
            re.search(r'\bWITH\s+RECURSIVE\b', upper)
            and re.search(
                r'\b(?:ROW_NUMBER|RANK|DENSE_RANK|FIRST_VALUE|LAST_VALUE|NTH_VALUE|LAG|LEAD|NTILE|COUNT|SUM|AVG|MIN|MAX)\s*\([^)]*\)\s*OVER\b',
                upper,
                flags=re.DOTALL,
            )
            and re.search(r'\bEMPLOYEES\b', upper)
            and re.search(r'\bACCESS_LOGS\b', upper)
        ):
            candidates.append(statement)
    assert candidates, (
        'The script must actually execute SQL that uses a recursive CTE and a window '
        'function while querying employees and access_logs.'
    )


def load_and_validate_report():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} should be a file."

    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert isinstance(report_data, list), "The JSON root must be an array (list)."
    expected_data = get_expected_data()

    assert len(report_data) == len(expected_data), (
        f"Expected {len(expected_data)} records in the report, but found {len(report_data)}. "
        "Ensure employees with no access logs are excluded."
    )

    for i, (actual, expected) in enumerate(zip(report_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert set(actual.keys()) == REQUIRED_KEYS, (
            f"Record {i} must contain exactly the keys {sorted(REQUIRED_KEYS)}, "
            f"but contains {sorted(actual.keys())}."
        )
        assert type(actual['employee_id']) is int, f"Record {i}: employee_id must be an integer."
        assert type(actual['hierarchy_level']) is int, f"Record {i}: hierarchy_level must be an integer."
        assert type(actual['top_system']) is str, f"Record {i}: top_system must be a string."
        assert type(actual['top_system_access_count']) is int, (
            f"Record {i}: top_system_access_count must be an integer."
        )

        assert actual.get("employee_id") == expected["employee_id"], \
            f"Record {i}: Expected employee_id {expected['employee_id']}, got {actual.get('employee_id')}."
        assert actual.get("hierarchy_level") == expected["hierarchy_level"], \
            f"Record {i} (employee {expected['employee_id']}): Expected hierarchy_level {expected['hierarchy_level']}, got {actual.get('hierarchy_level')}."
        assert actual.get("top_system") == expected["top_system"], \
            f"Record {i} (employee {expected['employee_id']}): Expected top_system '{expected['top_system']}', got '{actual.get('top_system')}'. Check tie-breaking logic."
        assert actual.get("top_system_access_count") == expected["top_system_access_count"], \
            f"Record {i} (employee {expected['employee_id']}): Expected top_system_access_count {expected['top_system_access_count']}, got {actual.get('top_system_access_count')}."

    return report_data


def test_script_exists_executes_and_uses_required_sql():
    statements = run_script_and_get_trace()
    assert_required_sql_was_executed(statements)


def test_report_exists():
    """Test that the compliance report JSON file was created."""
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} should be a file."


def test_report_format_and_content():
    """Test that the compliance report contains the correct JSON structure and data."""
    load_and_validate_report()


def test_script_handles_unseen_database_data():
    backup_dir = tempfile.mkdtemp(prefix='audit_backup_')
    db_backup = os.path.join(backup_dir, 'audit.db')
    report_backup = os.path.join(backup_dir, 'compliance_report.json')
    shutil.copy2(DB_PATH, db_backup)
    report_existed = os.path.isfile(REPORT_PATH)
    if report_existed:
        shutil.copy2(REPORT_PATH, report_backup)

    try:
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.executescript('''
            CREATE TABLE employees (
                emp_id INTEGER PRIMARY KEY,
                name TEXT,
                manager_id INTEGER
            );
            CREATE TABLE access_logs (
                log_id INTEGER PRIMARY KEY,
                emp_id INTEGER,
                system_name TEXT,
                access_date DATE
            );
        ''')
        cursor.executemany('INSERT INTO employees VALUES (?, ?, ?)', [
            (41, 'Root', None),
            (8, 'North', 41),
            (73, 'South', 41),
            (19, 'Deep', 8),
            (55, 'Deeper', 19),
            (6, 'No Logs', 73),
        ])
        cursor.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', [
            (1, 41, 'Console', '2026-01-01'),
            (2, 8, 'Zulu', '2026-01-02'),
            (3, 8, 'Alpha', '2026-01-03'),
            (4, 19, 'Ledger', '2026-01-04'),
            (5, 19, 'Ledger', '2026-01-05'),
            (6, 19, 'Mail', '2026-01-06'),
            (7, 55, 'Beta', '2026-01-07'),
            (8, 55, 'Beta', '2026-01-08'),
            (9, 55, 'Alpha', '2026-01-09'),
            (10, 55, 'Alpha', '2026-01-10'),
            (11, 73, 'Portal', '2026-01-11'),
            (12, 73, 'Portal', '2026-01-12'),
            (13, 73, 'Portal', '2026-01-13'),
        ])
        conn.commit()
        conn.close()

        statements = run_script_and_get_trace()
        assert_required_sql_was_executed(statements)
        load_and_validate_report()
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.copy2(db_backup, DB_PATH)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        if report_existed:
            shutil.copy2(report_backup, REPORT_PATH)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
