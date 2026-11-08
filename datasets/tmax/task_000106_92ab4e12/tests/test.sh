#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gc
import json
import os
import re
import runpy
import signal
import sqlite3
import stat
import subprocess
import uuid

import pytest

DB_PATH = '/home/user/backups.db'
JSON_PATH = '/home/user/summary.json'
SCRIPT_PATH = '/home/user/analyze_backups.py'


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"The path {SCRIPT_PATH} is not a regular file."
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_summary():
    try:
        with open(JSON_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {JSON_PATH} as valid JSON: {e}")


def expected_values(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        WITH RECURSIVE chain AS (
            SELECT backup_id, size_bytes FROM backups WHERE backup_id = 1
            UNION ALL
            SELECT b.backup_id, b.size_bytes FROM backups b
            INNER JOIN chain c ON b.parent_id = c.backup_id
        )
        SELECT SUM(size_bytes) FROM chain;
    """)
    chain_total = cursor.fetchone()[0]

    cursor.execute("""
        WITH ranked AS (
            SELECT backup_id, job_name, size_bytes,
                   ROW_NUMBER() OVER (
                       PARTITION BY job_name
                       ORDER BY size_bytes DESC, backup_id DESC
                   ) AS rn
            FROM backups
        )
        SELECT job_name, backup_id FROM ranked WHERE rn = 1;
    """)
    largest = {row[0]: row[1] for row in cursor.fetchall()}
    conn.close()
    return chain_total, largest


def assert_summary(summary, expected_chain, expected_largest):
    assert "chain_1_total_size" in summary, "Key 'chain_1_total_size' is missing in the JSON."
    assert "largest_per_job" in summary, "Key 'largest_per_job' is missing in the JSON."
    assert summary["chain_1_total_size"] == expected_chain, (
        f"Expected chain_1_total_size to be {expected_chain}, "
        f"but got {summary['chain_1_total_size']}."
    )
    assert summary["largest_per_job"] == expected_largest, (
        f"Expected largest_per_job to be {expected_largest}, "
        f"but got {summary['largest_per_job']}."
    )


def test_summary_json_exists():
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} was not created."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."


def test_summary_json_content():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    expected_chain, expected_largest = expected_values(DB_PATH)
    assert_summary(load_summary(), expected_chain, expected_largest)


def test_script_uses_required_sql_on_unseen_data():
    original_db = open(DB_PATH, 'rb').read()
    original_json = open(JSON_PATH, 'rb').read() if os.path.exists(JSON_PATH) else None
    suffix = uuid.uuid4().hex[:10]
    jobs = [f'alpha_{suffix}', f'beta_{suffix}', f'gamma_{suffix}', f'delta_{suffix}']
    base = int.from_bytes(os.urandom(3), 'big') + 10000
    executed_sql = []

    real_connect = sqlite3.connect

    class CursorProxy:
        def __init__(self, cursor):
            self._cursor = cursor

        def execute(self, sql, *args, **kwargs):
            executed_sql.append(str(sql))
            self._cursor.execute(sql, *args, **kwargs)
            return self

        def executemany(self, sql, *args, **kwargs):
            executed_sql.append(str(sql))
            self._cursor.executemany(sql, *args, **kwargs)
            return self

        def executescript(self, sql, *args, **kwargs):
            executed_sql.append(str(sql))
            self._cursor.executescript(sql, *args, **kwargs)
            return self

        def __iter__(self):
            return iter(self._cursor)

        def __getattr__(self, name):
            return getattr(self._cursor, name)

    class ConnectionProxy:
        def __init__(self, connection):
            self._connection = connection

        def cursor(self, *args, **kwargs):
            return CursorProxy(self._connection.cursor(*args, **kwargs))

        def execute(self, sql, *args, **kwargs):
            executed_sql.append(str(sql))
            return CursorProxy(self._connection.execute(sql, *args, **kwargs))

        def executemany(self, sql, *args, **kwargs):
            executed_sql.append(str(sql))
            return CursorProxy(self._connection.executemany(sql, *args, **kwargs))

        def executescript(self, sql, *args, **kwargs):
            executed_sql.append(str(sql))
            return CursorProxy(self._connection.executescript(sql, *args, **kwargs))

        def __enter__(self):
            self._connection.__enter__()
            return self

        def __exit__(self, *args):
            return self._connection.__exit__(*args)

        def __getattr__(self, name):
            return getattr(self._connection, name)

    def logged_connect(*args, **kwargs):
        return ConnectionProxy(real_connect(*args, **kwargs))

    try:
        os.remove(DB_PATH)
        conn = real_connect(DB_PATH)
        conn.execute('''CREATE TABLE backups (
            backup_id INTEGER PRIMARY KEY,
            parent_id INTEGER,
            size_bytes INTEGER,
            job_name TEXT
        )''')
        rows = [
            (1, None, base + 11, jobs[0]),
            (2, 1, base + 22, jobs[1]),
            (3, 2, base + 22, jobs[1]),
            (4, None, base * 9, jobs[0]),
            (5, 1, base + 33, jobs[2]),
            (6, 5, base + 33, jobs[2]),
            (7, 4, base * 8, jobs[1]),
            (8, 3, base + 44, jobs[3]),
            (9, None, base + 44, jobs[3]),
        ]
        conn.executemany('INSERT INTO backups VALUES (?, ?, ?, ?)', rows)
        conn.commit()
        conn.close()

        expected_chain, expected_largest = expected_values(DB_PATH)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)

        sqlite3.connect = logged_connect

        def timeout_handler(signum, frame):
            raise TimeoutError(f"Executing {SCRIPT_PATH} timed out")

        old_handler = signal.signal(signal.SIGALRM, timeout_handler)
        signal.alarm(20)
        try:
            runpy.run_path(SCRIPT_PATH, run_name='__main__')
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, old_handler)
            sqlite3.connect = real_connect

        assert os.path.isfile(JSON_PATH), f"Executing {SCRIPT_PATH} did not create {JSON_PATH}."
        assert_summary(load_summary(), expected_chain, expected_largest)

        recursive_queries = [
            sql for sql in executed_sql
            if re.search(r'\bWITH\s+RECURSIVE\b', sql, re.IGNORECASE)
        ]
        window_queries = [
            sql for sql in executed_sql
            if re.search(r'\bOVER\s*\(', sql, re.IGNORECASE)
        ]
        assert recursive_queries, "The script did not execute a recursive CTE query."
        assert any(
            re.search(r'\bparent_id\b', sql, re.IGNORECASE)
            and re.search(r'\bsize_bytes\b', sql, re.IGNORECASE)
            for sql in recursive_queries
        ), "The recursive CTE query did not traverse parent_id and aggregate backup sizes."
        assert window_queries, "The script did not execute a SQL window-function query."
        assert any(
            re.search(r'PARTITION\s+BY\s+(?:\w+\.)?job_name\b', sql, re.IGNORECASE)
            and re.search(r'\bsize_bytes\b', sql, re.IGNORECASE)
            and re.search(r'\bbackup_id\b', sql, re.IGNORECASE)
            for sql in window_queries
        ), "The window query did not partition by job_name and rank using size and backup_id."
    finally:
        sqlite3.connect = real_connect
        gc.collect()
        with open(DB_PATH, 'wb') as f:
            f.write(original_db)
        if original_json is None:
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
        else:
            with open(JSON_PATH, 'wb') as f:
                f.write(original_json)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
