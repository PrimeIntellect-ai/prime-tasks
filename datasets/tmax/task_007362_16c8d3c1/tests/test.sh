#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HARNESS_EOF' > /tmp/sqlite_trace_harness.py
import json
import os
import re
import runpy
import sqlite3
import sys

trace = []
_SENTINEL = object()
_real_connect = sqlite3.connect

def record(sql, params):
    trace.append({
        "sql": str(sql),
        "has_params": params is not _SENTINEL,
    })

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, params=_SENTINEL):
        record(sql, params)
        if params is _SENTINEL:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, params)
        return self

    def executemany(self, sql, params):
        record(sql, params)
        self._cursor.executemany(sql, params)
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

    def execute(self, sql, params=_SENTINEL):
        record(sql, params)
        if params is _SENTINEL:
            return CursorProxy(self._connection.execute(sql))
        return CursorProxy(self._connection.execute(sql, params))

    def executemany(self, sql, params):
        record(sql, params)
        return CursorProxy(self._connection.executemany(sql, params))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def traced_connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = traced_connect
script = sys.argv[1]
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with open(os.environ["SQLITE_TRACE_PATH"], "w") as f:
        json.dump(trace, f)
HARNESS_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

CSV_PATH = '/home/user/violations.csv'
DB_PATH = '/home/user/employees.db'
JSONL_PATH = '/home/user/access_logs.jsonl'
HEADER = ['timestamp', 'user_id', 'name', 'role', 'resource']


def expected_from_inputs():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, name, role FROM users")
    users = {row[0]: {'name': row[1], 'role': row[2]} for row in c.fetchall()}
    c.execute("SELECT role, resource FROM permissions")
    perms = set(c.fetchall())
    conn.close()

    expected = []
    with open(JSONL_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            log = json.loads(line)
            user = users.get(log['user_id'])
            if not user:
                continue
            if (user['role'], log['resource']) not in perms:
                expected.append({
                    'timestamp': log['timestamp'],
                    'user_id': str(log['user_id']),
                    'name': user['name'],
                    'role': user['role'],
                    'resource': log['resource'],
                })
    expected.sort(key=lambda row: row['timestamp'])
    return expected


def assert_csv(expected):
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            raise AssertionError("CSV file is empty.")
        assert header == HEADER, f"CSV header is incorrect: {header}"
        rows = list(reader)

    assert len(rows) == len(expected), \
        f"Expected {len(expected)} violations, found {len(rows)}."
    for i, (row, wanted) in enumerate(zip(rows, expected)):
        assert row[0] == wanted['timestamp'], f"Row {i+1} timestamp mismatch: expected {wanted['timestamp']}, got {row[0]}"
        assert row[1] == wanted['user_id'], f"Row {i+1} user_id mismatch: expected {wanted['user_id']}, got {row[1]}"
        assert row[2] == wanted['name'], f"Row {i+1} name mismatch: expected {wanted['name']}, got {row[2]}"
        assert row[3] == wanted['role'], f"Row {i+1} role mismatch: expected {wanted['role']}, got {row[3]}"
        assert row[4] == wanted['resource'], f"Row {i+1} resource mismatch: expected {wanted['resource']}, got {row[4]}"


def find_scripts():
    scripts = []
    roots = ['/home/user', '/tmp', '/workspace']
    excluded = {
        '/tmp/test_final_state.py',
        '/tmp/sqlite_trace_harness.py',
    }
    skipped_dirs = {'.cache', '.git', '.pytest_cache', '__pycache__', 'site-packages', 'dist-packages', 'venv', '.venv'}
    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in skipped_dirs]
            for name in files:
                path = os.path.abspath(os.path.join(current, name))
                if name.endswith('.py') and path not in excluded:
                    scripts.append(path)
    return sorted(set(scripts))


def make_dynamic_inputs(token):
    ids = [secrets.randbelow(500000) + 1000 for _ in range(4)]
    while len(set(ids)) != 4:
        ids = [secrets.randbelow(500000) + 1000 for _ in range(4)]

    names = [f'Name_{token}_{i}' for i in range(4)]
    roles = [f'Role_{token}_{i}' for i in range(4)]
    resources = [f'Resource_{token}_{i}' for i in range(5)]

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, role TEXT)')
    c.execute('CREATE TABLE permissions (role TEXT, resource TEXT)')
    c.executemany('INSERT INTO users VALUES (?,?,?)', list(zip(ids, names, roles)))
    c.executemany('INSERT INTO permissions VALUES (?,?)', [
        (roles[0], resources[0]),
        (roles[0], resources[1]),
        (roles[1], resources[1]),
        (roles[2], resources[2]),
        (roles[3], resources[3]),
    ])
    conn.commit()
    conn.close()

    logs = [
        {'timestamp': '2041-07-03T10:30:00Z', 'user_id': ids[2], 'resource': resources[4]},
        {'timestamp': '2041-07-03T10:05:00Z', 'user_id': ids[0], 'resource': resources[0]},
        {'timestamp': '2041-07-03T10:20:00Z', 'user_id': ids[1], 'resource': resources[3]},
        {'timestamp': '2041-07-03T10:10:00Z', 'user_id': ids[3], 'resource': resources[0]},
        {'timestamp': '2041-07-03T10:40:00Z', 'user_id': ids[3], 'resource': resources[3]},
        {'timestamp': '2041-07-03T10:15:00Z', 'user_id': ids[2], 'resource': resources[2]},
    ]
    with open(JSONL_PATH, 'w') as f:
        for entry in logs:
            f.write(json.dumps(entry) + '\n')


def trace_uses_parameterized_rbac_queries(trace):
    covered = set()
    for call in trace:
        sql = call.get('sql', '')
        lower = sql.lower()
        is_select = bool(re.match(r'^\s*(select|with)\b', lower))
        mentioned = {table for table in ('users', 'permissions') if re.search(r'\b' + table + r'\b', lower)}
        if not mentioned or not is_select:
            continue

        has_placeholder = ('?' in sql or re.search(r'(?<!:):[A-Za-z_][A-Za-z0-9_]*', sql) is not None)
        parameterized = bool(call.get('has_params')) and has_placeholder
        if not parameterized:
            return False
        covered.update(mentioned)
    return covered == {'users', 'permissions'}


def test_final_state_and_script():
    # Preserve all original checks against the supplied records.
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    assert os.path.exists(JSONL_PATH), f"Log file {JSONL_PATH} is missing."
    assert_csv(expected_from_inputs())

    scripts = find_scripts()
    assert scripts, "No Python cross-referencing script was created."

    backups = {}
    for path in (DB_PATH, JSONL_PATH, CSV_PATH):
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    try:
        token = secrets.token_hex(8)
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        make_dynamic_inputs(token)
        dynamic_db = open(DB_PATH, 'rb').read()
        dynamic_logs = open(JSONL_PATH, 'rb').read()
        expected = expected_from_inputs()

        accepted = False
        diagnostics = []
        for script in scripts:
            with open(DB_PATH, 'wb') as f:
                f.write(dynamic_db)
            with open(JSONL_PATH, 'wb') as f:
                f.write(dynamic_logs)
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)

            trace_file = tempfile.mktemp(prefix='sqlite_trace_', suffix='.json')
            env = os.environ.copy()
            env['SQLITE_TRACE_PATH'] = trace_file
            try:
                result = subprocess.run(
                    ['python3', '/tmp/sqlite_trace_harness.py', script],
                    cwd=os.path.dirname(script) or '/', env=env,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=20
                )
                if result.returncode != 0:
                    diagnostics.append(f"{script}: exited {result.returncode}")
                    continue
                try:
                    assert_csv(expected)
                except Exception as exc:
                    diagnostics.append(f"{script}: incorrect dynamic CSV ({exc})")
                    continue
                if not os.path.exists(trace_file):
                    diagnostics.append(f"{script}: produced no SQLite trace")
                    continue
                with open(trace_file, 'r') as f:
                    trace = json.load(f)
                if not trace_uses_parameterized_rbac_queries(trace):
                    diagnostics.append(f"{script}: did not use parameterized SELECT queries for both users and permissions")
                    continue
                accepted = True
                break
            except subprocess.TimeoutExpired:
                diagnostics.append(f"{script}: timed out")
            finally:
                if os.path.exists(trace_file):
                    os.remove(trace_file)

        assert accepted, "No created Python script generated the correct CSV from changed inputs using parameterized RBAC queries. " + '; '.join(diagnostics)
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
