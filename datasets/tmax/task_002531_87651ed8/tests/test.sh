#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import sqlite3
import stat
import subprocess

import pytest

REPORT_PATH = '/home/user/compliance_report.json'
DB_PATH = '/home/user/audit_data.db'
SCRIPT_PATH = '/home/user/audit.py'


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'audit.py exited with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def load_report():
    assert os.path.exists(REPORT_PATH), f'Missing {REPORT_PATH}'
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{REPORT_PATH} does not contain valid JSON')


def index_columns(conn, table):
    result = []
    for row in conn.execute(f'PRAGMA index_list("{table}")'):
        index_name = row[1].replace('"', '""')
        columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{index_name}")')]
        result.append(columns)
    return result


def assert_proper_indexes(conn):
    employee_indexes = index_columns(conn, 'employees')
    system_indexes = index_columns(conn, 'systems')
    exception_indexes = index_columns(conn, 'exceptions')
    log_indexes = index_columns(conn, 'access_logs')

    assert any(cols[:1] == ['emp_id'] for cols in employee_indexes), \
        'employees.emp_id must be indexed as a join key'
    assert any(cols[:1] == ['sys_id'] for cols in system_indexes), \
        'systems.sys_id must be indexed as a join key'
    assert any(len(cols) >= 2 and set(cols[:2]) == {'emp_id', 'sys_id'} for cols in exception_indexes), \
        'exceptions must have a composite index on (emp_id, sys_id)'
    assert any(len(cols) >= 2 and set(cols[:2]) == {'emp_id', 'sys_id'} for cols in log_indexes), \
        'access_logs must have an index covering its employee and system join keys'


def test_audit_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT_PATH} must be a regular Python script'
    run_script()


def test_compliance_report_exists():
    """Test that the compliance report JSON file was created."""
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"


def test_compliance_report_content():
    """Test that the compliance report contains the correct aggregated violations."""
    assert os.path.exists(REPORT_PATH), f"Missing {REPORT_PATH}"

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} does not contain valid JSON")

    expected_data = [
        {
            "emp_id": 1,
            "name": "Alice",
            "violation_count": 3
        },
        {
            "emp_id": 3,
            "name": "Charlie",
            "violation_count": 2
        }
    ]

    assert isinstance(data, list), "The JSON output must be an array of objects"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}"

    for i, expected in enumerate(expected_data):
        assert data[i] == expected, f"Record at index {i} does not match expected output. Expected {expected}, got {data[i]}"


def test_indexes_created():
    """Test that indexes were created on the database to optimize queries."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
    indexes = cursor.fetchall()

    assert len(indexes) > 0, "No indexes were created on the database. The task requires creating indexes to optimize queries."
    assert_proper_indexes(conn)
    conn.close()


def test_script_computes_report_for_new_database():
    rng = random.Random(secrets.randbits(64))
    base = secrets.randbelow(500000) + 10000
    emp_ids = rng.sample(range(base, base + 5000), 5)
    sys_ids = rng.sample(range(base + 10000, base + 15000), 3)
    dept_ids = rng.sample(range(base + 20000, base + 25000), 3)

    employees = [
        (emp_ids[0], f'Employee-{secrets.token_hex(4)}', dept_ids[0]),
        (emp_ids[1], f'Employee-{secrets.token_hex(4)}', dept_ids[1]),
        (emp_ids[2], f'Employee-{secrets.token_hex(4)}', dept_ids[2]),
        (emp_ids[3], f'Employee-{secrets.token_hex(4)}', dept_ids[0]),
        (emp_ids[4], f'Employee-{secrets.token_hex(4)}', dept_ids[1]),
    ]
    systems = [
        (sys_ids[0], f'System-{secrets.token_hex(4)}', dept_ids[0]),
        (sys_ids[1], f'System-{secrets.token_hex(4)}', dept_ids[1]),
        (sys_ids[2], f'System-{secrets.token_hex(4)}', dept_ids[2]),
    ]
    exceptions = [(emp_ids[1], sys_ids[0])]

    access_pairs = [
        (emp_ids[0], sys_ids[0]),
        (emp_ids[0], sys_ids[1]),
        (emp_ids[0], sys_ids[1]),
        (emp_ids[0], sys_ids[2]),
        (emp_ids[1], sys_ids[1]),
        (emp_ids[1], sys_ids[0]),
        (emp_ids[1], sys_ids[2]),
        (emp_ids[1], sys_ids[2]),
        (emp_ids[1], sys_ids[2]),
        (emp_ids[2], sys_ids[2]),
        (emp_ids[2], sys_ids[0]),
        (emp_ids[3], sys_ids[0]),
        (emp_ids[3], sys_ids[1]),
        (emp_ids[3], sys_ids[1]),
        (emp_ids[4], sys_ids[1]),
    ]
    rng.shuffle(access_pairs)
    logs = [
        (i + 1, emp_id, sys_id, f'2026-07-{(i % 28) + 1:02d}T12:00:00')
        for i, (emp_id, sys_id) in enumerate(access_pairs)
    ]

    employee_by_id = {row[0]: row for row in employees}
    system_by_id = {row[0]: row for row in systems}
    exception_set = set(exceptions)
    counts = {}
    for _, emp_id, sys_id, _ in logs:
        employee = employee_by_id.get(emp_id)
        system = system_by_id.get(sys_id)
        if employee and system and employee[2] != system[2] and (emp_id, sys_id) not in exception_set:
            counts[emp_id] = counts.get(emp_id, 0) + 1

    expected = [
        {
            'emp_id': emp_id,
            'name': employee_by_id[emp_id][1],
            'violation_count': count,
        }
        for emp_id, count in counts.items()
    ]
    expected.sort(key=lambda row: (-row['violation_count'], row['emp_id']))

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE employees (emp_id INTEGER, name TEXT, department_id INTEGER)')
    conn.execute('CREATE TABLE systems (sys_id INTEGER, sys_name TEXT, owning_dept_id INTEGER)')
    conn.execute('CREATE TABLE exceptions (emp_id INTEGER, sys_id INTEGER)')
    conn.execute('CREATE TABLE access_logs (log_id INTEGER, emp_id INTEGER, sys_id INTEGER, timestamp TEXT)')
    conn.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees)
    conn.executemany('INSERT INTO systems VALUES (?, ?, ?)', systems)
    conn.executemany('INSERT INTO exceptions VALUES (?, ?)', exceptions)
    conn.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
    conn.commit()
    conn.close()

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    run_script()
    actual = load_report()

    assert isinstance(actual, list), 'The JSON output must be an array'
    for row in actual:
        assert isinstance(row, dict) and set(row) == {'emp_id', 'name', 'violation_count'}, \
            'Each result must contain only emp_id, name, and violation_count'
        assert type(row['emp_id']) is int
        assert type(row['name']) is str
        assert type(row['violation_count']) is int
    assert actual == expected, f'Expected dynamically computed report {expected}, got {actual}'

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes were created on the database. The task requires creating indexes to optimize queries."
    assert_proper_indexes(conn)
    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
