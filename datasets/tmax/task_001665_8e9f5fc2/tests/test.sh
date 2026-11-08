#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import sqlite3
import pytest

DB_PATH = '/home/user/company.db'
PLAN_BEFORE_PATH = '/home/user/plan_before.txt'
PLAN_AFTER_PATH = '/home/user/plan_after.txt'
REPORTS_CSV_PATH = '/home/user/reports.csv'

QUERY = '''
WITH RECURSIVE org_chart AS (
    SELECT id, name, manager_id FROM employees WHERE id = 42
    UNION ALL
    SELECT e.id, e.name, e.manager_id
    FROM employees e
    JOIN org_chart o ON e.manager_id = o.id
)
SELECT id, name, manager_id FROM org_chart ORDER BY id ASC;
'''


def original_employees():
    random.seed(42)
    rows = [(1, 'CEO', None)]
    for i in range(2, 10001):
        manager = random.randint(1, i - 1)
        if i == 42:
            manager = 5
        rows.append((i, f'Employee_{i}', manager))
    return rows


ORIGINAL_ROWS = original_employees()


def expected_report_rows():
    by_manager = {}
    by_id = {}
    for row in ORIGINAL_ROWS:
        by_id[row[0]] = row
        by_manager.setdefault(row[2], []).append(row[0])

    found = set()
    pending = [42]
    while pending:
        employee_id = pending.pop()
        if employee_id in found:
            continue
        found.add(employee_id)
        pending.extend(by_manager.get(employee_id, ()))
    return [by_id[employee_id] for employee_id in sorted(found)]


def read_plan(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read().splitlines()


def explain_details(conn):
    return [row[3] for row in conn.execute('EXPLAIN QUERY PLAN ' + QUERY)]


def test_database_original_data_is_intact():
    assert os.path.exists(DB_PATH), f'{DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute('PRAGMA table_info(employees)').fetchall()
        assert schema == [
            (0, 'id', 'INTEGER', 0, None, 1),
            (1, 'name', 'TEXT', 0, None, 0),
            (2, 'manager_id', 'INTEGER', 0, None, 0),
        ], f'Unexpected employees schema: {schema}'
        actual = conn.execute(
            'SELECT id, name, manager_id FROM employees ORDER BY id'
        ).fetchall()
    finally:
        conn.close()
    assert actual == ORIGINAL_ROWS, 'The original employees data was altered.'


def test_plan_before():
    """Verify plan_before is the actual pre-index plan for the recursive query."""
    assert os.path.exists(PLAN_BEFORE_PATH), f'{PLAN_BEFORE_PATH} does not exist.'
    content = '\n'.join(read_plan(PLAN_BEFORE_PATH)).upper()
    assert 'SCAN' in content, f"Expected to find 'SCAN' in {PLAN_BEFORE_PATH}, but it was not found."

    pristine = sqlite3.connect(':memory:')
    try:
        pristine.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
        pristine.executemany('INSERT INTO employees VALUES (?, ?, ?)', ORIGINAL_ROWS)
        expected = explain_details(pristine)
    finally:
        pristine.close()
    assert read_plan(PLAN_BEFORE_PATH) == expected, \
        'plan_before.txt is not the raw EXPLAIN QUERY PLAN output from the unoptimized database.'


def test_idx_manager_exists():
    """Verify idx_manager exists and indexes manager_id."""
    assert os.path.exists(DB_PATH), f'{DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        result = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_manager'"
        ).fetchone()
        assert result is not None, "Index 'idx_manager' does not exist in the database."
        columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_manager')")]
    finally:
        conn.close()
    assert columns == ['manager_id'], \
        f"Index 'idx_manager' must index manager_id; found columns {columns}."


def test_plan_after():
    """Verify plan_after is the actual optimized plan and uses idx_manager."""
    assert os.path.exists(PLAN_AFTER_PATH), f'{PLAN_AFTER_PATH} does not exist.'
    actual_file = read_plan(PLAN_AFTER_PATH)
    content = '\n'.join(actual_file).upper()
    assert 'SEARCH' in content or 'INDEX' in content, \
        f"Expected to find 'SEARCH' or 'INDEX' in {PLAN_AFTER_PATH}."
    assert 'IDX_MANAGER' in content, \
        f"Expected to find reference to 'idx_manager' in {PLAN_AFTER_PATH}."

    conn = sqlite3.connect(DB_PATH)
    try:
        expected = explain_details(conn)
    finally:
        conn.close()
    assert actual_file == expected, \
        'plan_after.txt is not the raw EXPLAIN QUERY PLAN output from the optimized database.'


def test_reports_csv():
    """Verify reports.csv has the exact independently derived original result."""
    assert os.path.exists(REPORTS_CSV_PATH), f'{REPORTS_CSV_PATH} does not exist.'
    expected_rows = expected_report_rows()

    with open(REPORTS_CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f'{REPORTS_CSV_PATH} is empty.')

        assert header == ['id', 'name', 'manager_id'], \
            f"Incorrect CSV header. Expected ['id', 'name', 'manager_id'], got {header}"

        actual_rows = []
        for row in reader:
            if len(row) != 3:
                pytest.fail(f'Row {row} does not have 3 columns.')
            try:
                emp_id = int(row[0])
                manager_id = int(row[2]) if row[2] else None
            except ValueError as exc:
                pytest.fail(f'Invalid integer value in CSV row {row}: {exc}')
            actual_rows.append((emp_id, row[1], manager_id))

    assert len(actual_rows) == len(expected_rows), \
        f'Expected {len(expected_rows)} rows in CSV, but found {len(actual_rows)}.'
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f'Row {i + 1} mismatch. Expected {expected}, got {actual}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
