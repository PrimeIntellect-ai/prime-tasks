#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import runpy
import shutil
import sqlite3 as real_sqlite3
import stat
import sys
import tempfile
import types
import uuid
from unittest.mock import patch

import pytest

ANALYZE_PATH = '/home/user/analyze.py'
DB_PATH = '/home/user/pipeline.db'
REPORT_PATH = '/home/user/pipeline_report.csv'
CAPTURED_SQL = []


class CursorWrapper:
    def __init__(self, cursor, statements):
        self._cursor = cursor
        self._statements = statements

    def execute(self, sql, parameters=()):
        self._statements.append(str(sql))
        return self._cursor.execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        self._statements.append(str(sql))
        return self._cursor.executemany(sql, seq_of_parameters)

    def executescript(self, sql):
        self._statements.append(str(sql))
        return self._cursor.executescript(sql)

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class ConnectionWrapper:
    def __init__(self, connection, statements):
        self._connection = connection
        self._statements = statements

    def cursor(self, *args, **kwargs):
        return CursorWrapper(self._connection.cursor(*args, **kwargs), self._statements)

    def execute(self, sql, parameters=()):
        self._statements.append(str(sql))
        return self._connection.execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        self._statements.append(str(sql))
        return self._connection.executemany(sql, seq_of_parameters)

    def executescript(self, sql):
        self._statements.append(str(sql))
        return self._connection.executescript(sql)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, exc_type, exc, tb):
        return self._connection.__exit__(exc_type, exc, tb)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def run_analyzer():
    statements = []
    connections = []
    fake_sqlite3 = types.ModuleType('sqlite3')
    for name in dir(real_sqlite3):
        setattr(fake_sqlite3, name, getattr(real_sqlite3, name))

    def connect(*args, **kwargs):
        wrapped = ConnectionWrapper(real_sqlite3.connect(*args, **kwargs), statements)
        connections.append(wrapped)
        return wrapped

    fake_sqlite3.connect = connect
    old_cwd = os.getcwd()
    try:
        os.chdir('/home/user')
        with patch.dict(sys.modules, {'sqlite3': fake_sqlite3}):
            runpy.run_path(ANALYZE_PATH, run_name='__main__')
    finally:
        os.chdir(old_cwd)
        for connection in connections:
            try:
                connection.close()
            except Exception:
                pass
    return statements


def read_rows():
    with open(REPORT_PATH, 'r', newline='') as f:
        return [row for row in csv.reader(f) if row]


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.exists(ANALYZE_PATH), f'{ANALYZE_PATH} is missing.'
    mode = os.stat(ANALYZE_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f'{ANALYZE_PATH} must be a regular Python file.'
    with open(ANALYZE_PATH, 'rb') as f:
        compile(f.read(), ANALYZE_PATH, 'exec')

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    CAPTURED_SQL.extend(run_analyzer())


def test_pipeline_report_exists():
    report_path = '/home/user/pipeline_report.csv'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."


def test_pipeline_report_content():
    report_path = '/home/user/pipeline_report.csv'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    expected_rows = [
        ['job_id', 'step', 'exec_time_sec', 'cumulative_time'],
        ['ingest', '0', '10', '10'],
        ['clean', '1', '25', '35'],
        ['transform', '2', '40', '75'],
        ['aggregate', '3', '15', '90'],
        ['report', '4', '5', '95']
    ]

    actual_rows = []
    with open(report_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_rows.append(row)

    assert actual_rows == expected_rows, (
        f"Content of {report_path} does not match the expected output. "
        f"Expected {expected_rows}, but got {actual_rows}."
    )


def test_required_sql_was_executed():
    def without_comments(sql):
        sql = re.sub(r'/\\*.*?\\*/', ' ', sql, flags=re.S)
        return re.sub(r'--[^\\n]*', ' ', sql)

    candidates = [without_comments(sql) for sql in CAPTURED_SQL]
    compliant = []
    for sql in candidates:
        if not re.search(r'\\bWITH\\s+RECURSIVE\\b', sql, re.I):
            continue
        if not re.search(r'\\b(?:FROM|JOIN)\\s+dependencies\\b', sql, re.I):
            continue
        if not re.search(r'\\bJOIN\\s+jobs\\b', sql, re.I):
            continue
        if not re.search(r'\\bSUM\\s*\\([^)]*exec_time_sec[^)]*\\)\\s*OVER\\s*\\(', sql, re.I | re.S):
            continue
        if not re.search(r'\\bOVER\\s*\\([^)]*ORDER\\s+BY[^)]]*(?:step|depth)', sql, re.I | re.S):
            continue
        if not re.search(r'\\bAS\\s+cumulative_time\\b', sql, re.I):
            continue
        compliant.append(sql)

    assert compliant, (
        'analyze.py did not execute a query containing the required recursive CTE, '
        'dependency traversal, jobs join, and ordered SUM window function.'
    )


def test_analyzer_handles_database_contents_instead_of_hardcoded_report():
    fd, backup_path = tempfile.mkstemp(prefix='pipeline-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    token = uuid.uuid4().hex[:10]
    first = f'stage_{token}_a'
    second = f'stage_{token}_b'
    dead_end = f'dead_{token}'
    times = {
        'ingest': 7,
        first: 19,
        second: 23,
        'report': 29,
        dead_end: 101,
    }
    dependencies = [
        (first, dead_end),
        (second, 'report'),
        ('ingest', first),
        (first, second),
    ]

    try:
        os.remove(DB_PATH)
        conn = real_sqlite3.connect(DB_PATH)
        conn.execute('CREATE TABLE jobs (job_id TEXT PRIMARY KEY, exec_time_sec INTEGER)')
        conn.execute('CREATE TABLE dependencies (parent_id TEXT, child_id TEXT)')
        conn.executemany('INSERT INTO jobs VALUES (?, ?)', list(times.items()))
        conn.executemany('INSERT INTO dependencies VALUES (?, ?)', dependencies)
        conn.commit()
        conn.close()

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        dynamic_sql = run_analyzer()
        assert dynamic_sql, 'analyze.py did not execute any SQL on the dynamic database.'

        children = {}
        for parent, child in dependencies:
            children.setdefault(parent, []).append(child)

        def find_path(node, seen):
            if node == 'report':
                return [node]
            for child in children.get(node, []):
                if child not in seen:
                    suffix = find_path(child, seen | {child})
                    if suffix:
                        return [node] + suffix
            return None

        path = find_path('ingest', {'ingest'})
        assert path is not None
        expected = [['job_id', 'step', 'exec_time_sec', 'cumulative_time']]
        cumulative = 0
        for step, job_id in enumerate(path):
            cumulative += times[job_id]
            expected.append([job_id, str(step), str(times[job_id]), str(cumulative)])

        assert read_rows() == expected, (
            'analyze.py did not derive the report from the current dependency graph and job times.'
        )
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.move(backup_path, DB_PATH)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_analyzer()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
