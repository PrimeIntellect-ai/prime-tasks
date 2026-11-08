#!/bin/bash
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_materialize_with_trace.py
import json
import runpy
import sqlite3 as real_sqlite3
import sys
import types

log_path, script_path = sys.argv[1], sys.argv[2]
real_connect = real_sqlite3.connect

def log_sql(sql):
    if isinstance(sql, str):
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(sql) + '\n')

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, '_cursor', cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

    def execute(self, sql, *args, **kwargs):
        log_sql(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        log_sql(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        log_sql(sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._cursor)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        log_sql(sql)
        return CursorProxy(self._connection.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        log_sql(sql)
        return CursorProxy(self._connection.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        log_sql(sql)
        return CursorProxy(self._connection.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

def traced_connect(*args, **kwargs):
    return ConnectionProxy(real_connect(*args, **kwargs))

shim = types.ModuleType('sqlite3')
for name in dir(real_sqlite3):
    setattr(shim, name, getattr(real_sqlite3, name))
shim.connect = traced_connect
sys.modules['sqlite3'] = shim
runpy.run_path(script_path, run_name='__main__')
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

CSV_PATH = '/home/user/paginated_tasks.csv'
DB_PATH = '/home/user/etl_tasks.db'
SCRIPT_PATH = '/home/user/materialize_graph.py'
RUNNER_PATH = '/tmp/run_materialize_with_trace.py'


def read_rows():
    actual_rows = []
    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # Skip empty lines if any
                actual_rows.append(row)
    return actual_rows


def run_script_and_check_cte():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    fd, trace_path = tempfile.mkstemp(prefix='sql_trace_', suffix='.jsonl')
    os.close(fd)
    try:
        result = subprocess.run(
            ['python3', RUNNER_PATH, trace_path, SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f'materialize_graph.py failed with exit code {result.returncode}: '
            f'{result.stderr}'
        )
        assert os.path.isfile(CSV_PATH), f'Output file not found at {CSV_PATH}'

        statements = []
        with open(trace_path, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip():
                    statements.append(json.loads(line))
        assert any(
            re.search(r'\bWITH\s+RECURSIVE\b', sql, re.IGNORECASE | re.DOTALL)
            and re.search(r'\btasks\b', sql, re.IGNORECASE)
            for sql in statements
        ), 'The script did not execute a Recursive CTE against the tasks table'
    finally:
        if os.path.exists(trace_path):
            os.remove(trace_path)


@pytest.fixture(scope='module', autouse=True)
def execute_submission():
    assert os.path.lexists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode) and not stat.S_ISLNK(mode), (
        f'{SCRIPT_PATH} must be a regular Python source file'
    )
    run_script_and_check_cte()


def test_csv_exists():
    """Test that the output CSV file exists."""
    assert os.path.isfile(CSV_PATH), f"Output file not found at {CSV_PATH}"


def test_csv_contents():
    """Test that the CSV contains exactly the expected paginated results."""
    expected_rows = [
        ['E', '2', 'B'],
        ['J', '3', 'F'],
        ['I', '3', 'E'],
        ['H', '3', 'C'],
        ['G', '3', 'C']
    ]

    actual_rows = []
    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # Skip empty lines if any
                actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def make_dynamic_data():
    token = secrets.token_hex(6).upper()
    rows = [('ROOT', None, 'SUCCESS', secrets.randbelow(9000) + 1)]
    level1 = [f'L1_{token}_{i}' for i in range(8)]
    for i, task_id in enumerate(level1):
        status = 'FAILED' if i == 2 else 'SUCCESS'
        rows.append((task_id, 'ROOT', status, secrets.randbelow(9000) + 1))
        for j in range(2):
            child = f'L2_{token}_{i}_{j}'
            child_status = 'FAILED' if (i == 5 and j == 1) else 'SUCCESS'
            rows.append((child, task_id, child_status, secrets.randbelow(9000) + 1))
            grandchild = f'L3_{token}_{i}_{j}'
            rows.append((grandchild, child, 'SUCCESS', secrets.randbelow(9000) + 1))
    return rows


def expected_page(rows):
    by_parent = {}
    status = {}
    exec_time = {}
    for task_id, parent_id, task_status, duration in rows:
        by_parent.setdefault(parent_id, []).append(task_id)
        status[task_id] = task_status
        exec_time[task_id] = duration

    materialized = []
    stack = [('ROOT', 0, None)]
    while stack:
        task_id, depth, parent_id = stack.pop()
        if status[task_id] == 'FAILED':
            continue
        materialized.append((task_id, depth, parent_id, exec_time[task_id]))
        for child in by_parent.get(task_id, []):
            stack.append((child, depth + 1, task_id))

    materialized.sort(key=lambda row: (row[1], -row[3], row[0]))
    page = materialized[5:10]
    assert len(page) == 5
    return [[task_id, str(depth), parent_id or ''] for task_id, depth, parent_id, _ in page]


def test_dynamic_database_is_queried_and_output_is_generated():
    fd, backup_path = tempfile.mkstemp(prefix='etl_tasks_backup_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        for _ in range(2):
            rows = make_dynamic_data()
            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            try:
                conn.execute('CREATE TABLE tasks (id TEXT, parent_id TEXT, status TEXT, exec_time INTEGER)')
                conn.executemany('INSERT INTO tasks VALUES (?,?,?,?)', rows)
                conn.commit()
            finally:
                conn.close()

            run_script_and_check_cte()
            actual = read_rows()
            expected = expected_page(rows)
            assert actual == expected, (
                'The script did not generate the correct paginated result from the '
                f'current SQLite database. Expected {expected}, got {actual}.'
            )
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
