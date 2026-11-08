#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

DB_PATH = '/home/user/etl_data.db'
JSON_PATH = '/home/user/aggregated_sales.json'
SCRIPT_PATH = '/home/user/process_hierarchy.py'

ORIGINAL_ROWS = [
    (1, 1, None, 100.0, '2023-10-01 10:00:00'),
    (2, 1, None, 150.0, '2023-10-01 12:00:00'),
    (3, 2, 1, 200.0, '2023-10-01 09:00:00'),
    (4, 2, 1, 220.0, '2023-10-01 11:00:00'),
    (5, 3, 1, 300.0, '2023-10-01 10:30:00'),
    (6, 4, 2, 50.0, '2023-10-01 08:00:00'),
    (7, 4, 2, 80.0, '2023-10-01 12:30:00'),
    (8, 5, 2, 120.0, '2023-10-01 10:00:00'),
    (9, 6, 4, 10.0, '2023-10-01 09:15:00'),
    (10, 7, 3, 40.0, '2023-10-01 07:00:00'),
    (11, 7, 3, 45.0, '2023-10-01 13:00:00'),
]


def compute_expected_aggregates(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('SELECT emp_id, manager_id, sales_amount, updated_at FROM sales_raw')
    rows = c.fetchall()
    conn.close()

    latest_records = {}
    for emp_id, manager_id, sales_amount, updated_at in rows:
        if emp_id not in latest_records or updated_at > latest_records[emp_id][2]:
            latest_records[emp_id] = (manager_id, sales_amount, updated_at)

    children = {}
    sales = {}
    for emp_id, (manager_id, sales_amount, _) in latest_records.items():
        sales[emp_id] = sales_amount
        children.setdefault(manager_id, []).append(emp_id)

    def get_inclusive_sales(eid):
        total = sales[eid]
        for child_id in children.get(eid, []):
            total += get_inclusive_sales(child_id)
        return total

    return [
        {'emp_id': emp_id, 'total_inclusive_sales': get_inclusive_sales(emp_id)}
        for emp_id in sorted(sales)
    ]


def file_digest(path):
    if not os.path.exists(path):
        return None
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def database_state():
    return {
        path: file_digest(path)
        for path in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm', DB_PATH + '-journal')
    }


def write_database(records):
    tmp_path = DB_PATH + '.verifier-new'
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    conn = sqlite3.connect(tmp_path)
    conn.execute('''
        CREATE TABLE sales_raw (
            record_id INTEGER PRIMARY KEY,
            emp_id INTEGER,
            manager_id INTEGER,
            sales_amount REAL,
            updated_at TEXT
        )
    ''')
    conn.executemany('INSERT INTO sales_raw VALUES (?, ?, ?, ?, ?)', records)
    conn.commit()
    conn.close()
    os.replace(tmp_path, DB_PATH)


def run_submission():
    if os.path.lexists(JSON_PATH):
        if os.path.isdir(JSON_PATH) and not os.path.islink(JSON_PATH):
            shutil.rmtree(JSON_PATH)
        else:
            os.unlink(JSON_PATH)

    workdir = tempfile.mkdtemp(prefix='hierarchy-verifier-')
    harness_path = os.path.join(workdir, 'runner.py')
    trace_path = os.path.join(workdir, 'trace.json')
    harness = r'''
import json
import runpy
import sqlite3
import sys

script_path, trace_path = sys.argv[1], sys.argv[2]
real_connect = sqlite3.connect
traces = []
write_actions = {
    getattr(sqlite3, name) for name in (
        'SQLITE_INSERT', 'SQLITE_UPDATE', 'SQLITE_DELETE',
        'SQLITE_CREATE_INDEX', 'SQLITE_CREATE_TABLE',
        'SQLITE_CREATE_TEMP_INDEX', 'SQLITE_CREATE_TEMP_TABLE',
        'SQLITE_CREATE_TEMP_TRIGGER', 'SQLITE_CREATE_TEMP_VIEW',
        'SQLITE_CREATE_TRIGGER', 'SQLITE_CREATE_VIEW',
        'SQLITE_CREATE_VTABLE', 'SQLITE_DROP_INDEX', 'SQLITE_DROP_TABLE',
        'SQLITE_DROP_TEMP_INDEX', 'SQLITE_DROP_TEMP_TABLE',
        'SQLITE_DROP_TEMP_TRIGGER', 'SQLITE_DROP_TEMP_VIEW',
        'SQLITE_DROP_TRIGGER', 'SQLITE_DROP_VIEW', 'SQLITE_DROP_VTABLE',
        'SQLITE_ALTER_TABLE', 'SQLITE_ATTACH', 'SQLITE_DETACH',
        'SQLITE_REINDEX', 'SQLITE_ANALYZE'
    ) if hasattr(sqlite3, name)
}

def checked_connect(*args, **kwargs):
    conn = real_connect(*args, **kwargs)
    conn.set_trace_callback(traces.append)
    def authorize(action, arg1, arg2, database, source):
        if action in write_actions:
            return sqlite3.SQLITE_DENY
        return sqlite3.SQLITE_OK
    conn.set_authorizer(authorize)
    return conn

sqlite3.connect = checked_connect
try:
    runpy.run_path(script_path, run_name='__main__')
finally:
    with open(trace_path, 'w') as f:
        json.dump(traces, f)
'''
    with open(harness_path, 'w') as f:
        f.write(harness)

    before = database_state()
    try:
        result = subprocess.run(
            [sys.executable, harness_path, SCRIPT_PATH, trace_path],
            cwd='/home/user', text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            'process_hierarchy.py failed when executed.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert database_state() == before, 'The submission modified the SQLite database.'
        assert os.path.exists(trace_path), 'No SQL execution trace was produced.'
        with open(trace_path) as f:
            traces = json.load(f)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    qualifying = []
    for statement in traces:
        if (re.search(r'\bWITH\s+RECURSIVE\b', statement, re.I | re.S)
                and re.search(r'\bROW_NUMBER\s*\(\s*\)\s*OVER\s*\(', statement, re.I | re.S)):
            qualifying.append(statement)
    assert qualifying, (
        'The executed SQL must use a recursive CTE and ROW_NUMBER() window function.'
    )


def assert_json_matches(expected):
    assert os.path.exists(JSON_PATH), (
        f'Output file missing at {JSON_PATH}. Did your script generate it?'
    )
    assert os.path.isfile(JSON_PATH), f'Expected a file at {JSON_PATH}, but found a directory.'

    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'Output file at {JSON_PATH} is not valid JSON: {exc}')

    assert isinstance(data, list), 'JSON output must be a list of objects (dictionaries).'
    assert len(data) == len(expected), (
        f'Expected {len(expected)} records in the JSON, got {len(data)}.'
    )

    for i, (actual_row, expected_row) in enumerate(zip(data, expected)):
        assert isinstance(actual_row, dict), f'Record at index {i} is not a JSON object.'
        assert 'emp_id' in actual_row, f"Record at index {i} is missing the 'emp_id' key."
        assert 'total_inclusive_sales' in actual_row, (
            f"Record at index {i} is missing the 'total_inclusive_sales' key."
        )
        assert set(actual_row) == {'emp_id', 'total_inclusive_sales'}, (
            f'Record at index {i} must contain exactly the required keys.'
        )
        assert actual_row['emp_id'] == expected_row['emp_id'], (
            f"Record at index {i} expected emp_id {expected_row['emp_id']}, "
            f"got {actual_row['emp_id']}."
        )
        assert actual_row['total_inclusive_sales'] == expected_row['total_inclusive_sales'], (
            f"Incorrect total_inclusive_sales for emp_id {expected_row['emp_id']}. "
            f"Expected {expected_row['total_inclusive_sales']}, "
            f"got {actual_row['total_inclusive_sales']}."
        )


def test_script_execution_sql_and_output():
    assert os.path.exists(DB_PATH), f'Database file missing at {DB_PATH}. Do not delete the database.'
    assert os.path.exists(SCRIPT_PATH), f'Required script missing at {SCRIPT_PATH}.'
    assert not os.path.islink(SCRIPT_PATH), 'process_hierarchy.py must be an actual script file.'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), 'process_hierarchy.py is not a regular file.'
    with open(SCRIPT_PATH, 'rb') as f:
        compile(f.read(), SCRIPT_PATH, 'exec')

    conn = sqlite3.connect(DB_PATH)
    current_rows = conn.execute('''
        SELECT record_id, emp_id, manager_id, sales_amount, updated_at
        FROM sales_raw ORDER BY record_id
    ''').fetchall()
    conn.close()
    assert current_rows == ORIGINAL_ROWS, 'The original SQLite database was modified before verification.'

    backup_dir = tempfile.mkdtemp(prefix='original-db-')
    backup_path = os.path.join(backup_dir, 'etl_data.db')
    shutil.copy2(DB_PATH, backup_path)

    rng = random.SystemRandom()
    latest = [rng.randrange(1000, 9000) for _ in range(7)]
    dynamic_records = [
        (1, 1, None, float(latest[0] + 97), '2025-01-01 08:00:00'),
        (2, 1, None, float(latest[0]), '2025-01-02 08:00:00'),
        (3, 2, 1, float(latest[1] + 83), '2025-01-01 09:00:00'),
        (4, 2, 1, float(latest[1]), '2025-01-03 09:00:00'),
        (5, 3, 1, float(latest[2]), '2025-01-02 10:00:00'),
        (6, 4, 2, float(latest[3] + 71), '2025-01-01 11:00:00'),
        (7, 4, 2, float(latest[3]), '2025-01-04 11:00:00'),
        (8, 5, 2, float(latest[4]), '2025-01-02 12:00:00'),
        (9, 6, 4, float(latest[5]), '2025-01-02 13:00:00'),
        (10, 7, 3, float(latest[6] + 59), '2025-01-01 14:00:00'),
        (11, 7, 3, float(latest[6]), '2025-01-05 14:00:00'),
    ]

    try:
        write_database(dynamic_records)
        dynamic_expected = compute_expected_aggregates(DB_PATH)
        run_submission()
        assert_json_matches(dynamic_expected)
    finally:
        shutil.copy2(backup_path, DB_PATH)
        for suffix in ('-wal', '-shm', '-journal'):
            if os.path.exists(DB_PATH + suffix):
                os.unlink(DB_PATH + suffix)
        shutil.rmtree(backup_dir, ignore_errors=True)

    expected = compute_expected_aggregates(DB_PATH)
    run_submission()
    assert_json_matches(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
