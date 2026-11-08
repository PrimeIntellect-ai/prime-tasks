#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import json
import os
import sqlite3

_trace_path = os.environ.get("SQL_TRACE_PATH")
_real_connect = sqlite3.connect

def _log(kind, sql, args=(), kwargs=None):
    if not _trace_path:
        return
    record = {
        "kind": kind,
        "sql": str(sql),
        "args": repr(args),
        "kwargs": repr(kwargs or {}),
    }
    with open(_trace_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(record) + "\n")

class TracedCursor:
    def __init__(self, inner):
        self._inner = inner

    def execute(self, sql, *args, **kwargs):
        _log("execute", sql, args, kwargs)
        self._inner.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        _log("executemany", sql, args, kwargs)
        self._inner.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        _log("executescript", sql, args, kwargs)
        self._inner.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)

class TracedConnection:
    def __init__(self, inner):
        self._inner = inner

    def cursor(self, *args, **kwargs):
        return TracedCursor(self._inner.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        _log("connection.execute", sql, args, kwargs)
        return TracedCursor(self._inner.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        _log("connection.executemany", sql, args, kwargs)
        return TracedCursor(self._inner.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        _log("connection.executescript", sql, args, kwargs)
        return TracedCursor(self._inner.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

def traced_connect(*args, **kwargs):
    return TracedConnection(_real_connect(*args, **kwargs))

sqlite3.connect = traced_connect
SITE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import uuid

import pytest

SCRIPT_PATH = '/home/user/generate_report.py'
DB_PATH = '/home/user/backup_metadata.db'
REPORT_PATH = '/home/user/report.json'


def read_report():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} was not created."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."
    try:
        with open(REPORT_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def assert_report(data, db_name, total, path):
    assert "database_name" in data, "Key 'database_name' missing from JSON output."
    assert data["database_name"] == db_name, \
        f"Expected database_name {db_name!r}, got {data['database_name']!r}."
    assert "correct_total_backup_size" in data, \
        "Key 'correct_total_backup_size' missing from JSON output."
    assert data["correct_total_backup_size"] == total, \
        f"Expected correct_total_backup_size to be {total}, got {data['correct_total_backup_size']}."
    assert "shortest_archive_path" in data, \
        "Key 'shortest_archive_path' missing from JSON output."
    assert data["shortest_archive_path"] == path, \
        f"Expected shortest_archive_path {path}, got {data['shortest_archive_path']}."


def test_report_json_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} was not created."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."


def test_report_json_content():
    data = read_report()
    assert_report(data, "billing-db", 15500, ["node_A", "node_C", "node_Z"])


def test_script_uses_recursive_cte():
    assert os.path.exists(SCRIPT_PATH), "Script file missing."
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().upper()
    assert "WITH RECURSIVE" in content, \
        "The script does not appear to use a Recursive CTE ('WITH RECURSIVE') as requested."


def test_script_uses_parameterized_queries():
    assert os.path.exists(SCRIPT_PATH), "Script file missing."
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    try:
        tree = ast.parse(content)
    except SyntaxError:
        pytest.fail("Script contains syntax errors.")

    execute_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr == 'execute':
                execute_calls.append(node)

    assert len(execute_calls) > 0, "No cursor.execute calls found in the script."
    parameterized = any(len(call.args) > 1 or call.keywords for call in execute_calls)
    assert parameterized, \
        "The script does not appear to use parameterized queries in cursor.execute()."


def create_dynamic_database(path):
    token = uuid.uuid4().hex
    db_one = "audit-' OR 1=1 --" + token
    db_two = "secondary-" + token

    names = {
        key: f"node_{key}_{token}"
        for key in ("a", "b", "c", "d", "z", "x", "y")
    }
    sizes_one = [
        1100 + secrets.randbelow(700),
        2400 + secrets.randbelow(700),
        3700 + secrets.randbelow(700),
    ]
    sizes_two = [5100 + secrets.randbelow(700), 6600 + secrets.randbelow(700)]

    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    try:
        cur = conn.cursor()
        cur.executescript('''
            CREATE TABLE databases (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE storage_nodes (id TEXT PRIMARY KEY, name TEXT, region TEXT);
            CREATE TABLE backup_jobs (
                id INTEGER PRIMARY KEY,
                db_id INTEGER,
                storage_id TEXT,
                size_bytes INTEGER,
                timestamp DATETIME
            );
            CREATE TABLE replication_links (source_id TEXT, target_id TEXT);
        ''')
        cur.executemany("INSERT INTO databases(id, name) VALUES (?, ?)",
                        [(101, db_one), (202, db_two)])
        cur.executemany("INSERT INTO storage_nodes(id, name, region) VALUES (?, ?, ?)", [
            ('a', names['a'], 'primary'),
            ('b', names['b'], 'edge'),
            ('c', names['c'], 'edge'),
            ('d', names['d'], 'edge'),
            ('z', names['z'], 'archive'),
            ('x', names['x'], 'primary'),
            ('y', names['y'], 'archive'),
        ])
        cur.executemany(
            "INSERT INTO backup_jobs(id, db_id, storage_id, size_bytes, timestamp) VALUES (?, ?, ?, ?, ?)",
            [
                (1, 101, 'x', sizes_one[0], '2025-01-01 01:00:00'),
                (2, 101, 'b', sizes_one[1], '2025-01-02 01:00:00'),
                (3, 101, 'a', sizes_one[2], '2025-01-03 01:00:00'),
                (4, 202, 'a', sizes_two[0], '2025-02-01 01:00:00'),
                (5, 202, 'x', sizes_two[1], '2025-02-02 01:00:00'),
            ],
        )
        # The first database has a unique two-hop shortest route and a longer
        # alternative. The cycle also requires a terminating traversal.
        cur.executemany("INSERT INTO replication_links(source_id, target_id) VALUES (?, ?)", [
            ('a', 'b'), ('b', 'z'),
            ('a', 'c'), ('c', 'd'), ('d', 'y'),
            ('b', 'a'),
            ('x', 'y'), ('x', 'c'),
        ])
        conn.commit()
    finally:
        conn.close()

    cases = [
        (db_one, sum(sizes_one), [names['a'], names['b'], names['z']]),
        (db_two, sum(sizes_two), [names['x'], names['y']]),
    ]
    return cases


def run_script(db_name, trace_path=None):
    env = os.environ.copy()
    if trace_path:
        env['PYTHONPATH'] = '/tmp' + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['SQL_TRACE_PATH'] = trace_path
        if os.path.exists(trace_path):
            os.remove(trace_path)
    else:
        env.pop('SQL_TRACE_PATH', None)
    return subprocess.run(
        [sys.executable, SCRIPT_PATH, db_name],
        cwd='/home/user', env=env, text=True, capture_output=True, timeout=15,
    )


def load_trace(path):
    assert os.path.exists(path), "The submitted script did not open SQLite while being executed."
    with open(path, 'r', encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def assert_required_sql_was_executed(records, db_name):
    assert records, "No SQLite statements were executed by the submitted script."
    sql_texts = [record['sql'] for record in records]
    upper = [sql.upper() for sql in sql_texts]

    window_queries = [sql for sql in upper
                      if re.search(r'\bOVER\s*\(', sql)
                      and 'BACKUP_JOBS' in sql and 'DATABASES' in sql]
    assert window_queries, \
        "Execution did not include a window-function analytical query over databases and backup_jobs."

    recursive_queries = [sql for sql in upper
                         if 'WITH RECURSIVE' in sql
                         and 'REPLICATION_LINKS' in sql
                         and 'STORAGE_NODES' in sql]
    assert recursive_queries, \
        "Execution did not include a recursive graph query over replication_links and storage_nodes."

    # The deliberately quote-containing runtime name must travel as a bound
    # value, never as text interpolated into an SQL statement.
    assert all(db_name not in sql for sql in sql_texts), \
        "The requested database name was interpolated directly into SQL."
    assert any(db_name in record['args'] or db_name in record['kwargs'] for record in records), \
        "The requested database name was not supplied to SQLite as a bound parameter."


def test_script_executes_correct_queries_on_unseen_database_and_graph():
    assert os.path.isfile(SCRIPT_PATH), "Script file missing."
    with open(DB_PATH, 'rb') as f:
        original_db = f.read()

    try:
        cases = create_dynamic_database(DB_PATH)
        for index, (db_name, expected_total, expected_path) in enumerate(cases):
            trace_path = f'/tmp/sql_trace_{index}.jsonl'
            result = run_script(db_name, trace_path)
            assert result.returncode == 0, \
                f"Script failed for an unseen database: {result.stderr or result.stdout}"
            assert_report(read_report(), db_name, expected_total, expected_path)
            assert_required_sql_was_executed(load_trace(trace_path), db_name)
    finally:
        with open(DB_PATH, 'wb') as f:
            f.write(original_db)
        final_run = run_script('billing-db')
        assert final_run.returncode == 0, \
            f"Script failed when restoring the required billing-db report: {final_run.stderr or final_run.stdout}"

    # The required final artifact must still be the billing-db report.
    assert_report(read_report(), "billing-db", 15500, ["node_A", "node_C", "node_Z"])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
