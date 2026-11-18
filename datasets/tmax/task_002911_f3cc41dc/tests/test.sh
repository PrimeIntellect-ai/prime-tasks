#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import runpy
import shutil
import sqlite3
import tempfile

import pytest

SCRIPT_PATH = "/home/user/audit.py"
DB_PATH = "/home/user/rbac.db"
REPORT_PATH = "/home/user/audit_report.json"
TRACE_PATH = "/tmp/audit_sql_trace.jsonl"
RUNNER_PATH = "/tmp/run_audit_instrumented.py"

EXPECTED_ORIGINAL = [
    {"audit_rank": 1, "username": "charlie", "assigned_role": "payment_admin"},
    {"audit_rank": 2, "username": "bob", "assigned_role": "finance_admin"},
    {"audit_rank": 3, "username": "eve", "assigned_role": "super_admin"},
    {"audit_rank": 4, "username": "alice", "assigned_role": "super_admin"},
]

RUNNER_SOURCE = r'''
import json
import runpy
import sqlite3

TRACE_PATH = "/tmp/audit_sql_trace.jsonl"
SCRIPT_PATH = "/home/user/audit.py"
_real_connect = sqlite3.connect

def log_sql(sql):
    if isinstance(sql, str):
        with open(TRACE_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(sql) + "\\n")

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor
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
    def __enter__(self):
        self._cursor.__enter__()
        return self
    def __exit__(self, *args):
        return self._cursor.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection
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
    def __getattr__(self, name):
        return getattr(self._connection, name)

def traced_connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = traced_connect
runpy.run_path(SCRIPT_PATH, run_name="__main__")
'''


def assert_report(data, expected):
    assert isinstance(data, list), f"Expected the JSON root to be a list, got {type(data).__name__}."
    assert len(data) == len(expected), f"Expected exactly {len(expected)} records in the report, got {len(data)}."
    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Record at index {i} is not a JSON object."
        for key in ["audit_rank", "username", "assigned_role"]:
            assert key in actual, f"Record at index {i} is missing key '{key}'."
            assert actual[key] == wanted[key], (
                f"Record at index {i} has incorrect '{key}'. "
                f"Expected {wanted[key]}, got {actual[key]}."
            )
        extra_keys = set(actual) - set(wanted)
        assert not extra_keys, f"Record at index {i} contains unexpected keys: {extra_keys}"


def load_report():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."
    try:
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def run_script():
    import subprocess
    open(TRACE_PATH, "w", encoding="utf-8").close()
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    result = subprocess.run(
        ["python3", RUNNER_PATH], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"audit.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return load_report()


def derive_expected(roles, hierarchy, permissions, users, user_roles):
    accessible = {role_id for role_id, resource in permissions
                  if resource == "SWIFT_PAYMENT_GATEWAY"}
    changed = True
    while changed:
        changed = False
        for parent, child in hierarchy:
            if child in accessible and parent not in accessible:
                accessible.add(parent)
                changed = True

    role_names = dict(roles)
    user_info = {uid: (username, created_at) for uid, username, created_at in users}
    rows = []
    for user_id, role_id in user_roles:
        if role_id in accessible:
            username, created_at = user_info[user_id]
            rows.append((created_at, username, role_names[role_id]))
    rows.sort(key=lambda row: row[0], reverse=True)
    return [
        {"audit_rank": rank, "username": username, "assigned_role": role_name}
        for rank, (_, username, role_name) in enumerate(rows, 1)
    ]


def create_challenge_database():
    roles = [
        (10, "settlement_leaf"), (20, "regional_finance"),
        (30, "global_treasury"), (40, "unrelated_guest"),
        (50, "emergency_payments"), (60, "executive_finance")
    ]
    hierarchy = [(20, 10), (30, 20), (30, 10), (60, 30)]
    permissions = [
        (10, "SWIFT_PAYMENT_GATEWAY"),
        (50, "SWIFT_PAYMENT_GATEWAY"),
        (40, "PRINTER_ACCESS")
    ]
    users = [
        (101, "nora", "2025-02-06 08:00:00"),
        (102, "omar", "2025-02-03 08:00:00"),
        (103, "priya", "2025-02-09 08:00:00"),
        (104, "quentin", "2025-02-10 08:00:00"),
        (105, "rhea", "2025-02-01 08:00:00"),
        (106, "soren", "2025-02-08 08:00:00")
    ]
    user_roles = [(101, 30), (102, 20), (103, 10), (104, 40), (105, 50), (106, 60)]

    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, created_at DATETIME);
        CREATE TABLE roles (id INTEGER PRIMARY KEY, role_name TEXT);
        CREATE TABLE role_hierarchy (parent_role_id INTEGER, child_role_id INTEGER);
        CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
        CREATE TABLE role_permissions (role_id INTEGER, resource_name TEXT);
    """)
    conn.executemany("INSERT INTO roles VALUES (?, ?)", roles)
    conn.executemany("INSERT INTO role_hierarchy VALUES (?, ?)", hierarchy)
    conn.executemany("INSERT INTO role_permissions VALUES (?, ?)", permissions)
    conn.executemany("INSERT INTO users VALUES (?, ?, ?)", users)
    conn.executemany("INSERT INTO user_roles VALUES (?, ?)", user_roles)
    conn.commit()
    conn.close()
    return derive_expected(roles, hierarchy, permissions, users, user_roles)


with open(RUNNER_PATH, "w", encoding="utf-8") as f:
    f.write(RUNNER_SOURCE)


def test_audit_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_audit_report_exists_and_original_content():
    assert_report(load_report(), EXPECTED_ORIGINAL)


def test_script_generates_original_report():
    assert_report(run_script(), EXPECTED_ORIGINAL)


def test_script_on_unseen_database_and_sql_features():
    fd, backup_path = tempfile.mkstemp(prefix="rbac-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    with open(REPORT_PATH, "rb") as f:
        original_report = f.read()

    try:
        expected = create_challenge_database()
        actual = run_script()
        assert_report(actual, expected)

        with open(TRACE_PATH, "r", encoding="utf-8") as f:
            statements = [json.loads(line) for line in f if line.strip()]
        assert statements, "No SQL statements were observed while audit.py ran."
        assert any(re.search(r"\bWITH\s+RECURSIVE\b", sql, re.I) for sql in statements), (
            "audit.py did not execute a recursive CTE."
        )
        window_pattern = re.compile(
            r"\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\([^)]*\)\s*OVER\s*\(", re.I | re.S
        )
        assert any(window_pattern.search(sql) for sql in statements), (
            "audit.py did not execute an SQL ranking window function."
        )
    finally:
        if os.path.exists(DB_PATH):
            os.unlink(DB_PATH)
        os.replace(backup_path, DB_PATH)
        with open(REPORT_PATH, "wb") as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
