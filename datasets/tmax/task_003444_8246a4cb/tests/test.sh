#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/sql_instrument
cat << 'PY_EOF' > /tmp/sql_instrument/sitecustomize.py
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("TRACE_SQL")

class TracedCursor:
    def __init__(self, cursor):
        self._cursor = cursor

    def _record(self, sql):
        if _trace_path and isinstance(sql, str):
            with open(_trace_path, "a", encoding="utf-8") as f:
                f.write("\n---STATEMENT---\n")
                f.write(sql)
                f.write("\n")

    def execute(self, sql, *args, **kwargs):
        self._record(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        self._record(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        self._record(sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class TracedConnection:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return TracedCursor(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        cursor = self.cursor()
        return cursor.execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        cursor = self.cursor()
        return cursor.executemany(sql, *args, **kwargs)

    def executescript(self, sql, *args, **kwargs):
        cursor = self.cursor()
        return cursor.executescript(sql, *args, **kwargs)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def traced_connect(*args, **kwargs):
    return TracedConnection(_real_connect(*args, **kwargs))

sqlite3.connect = traced_connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

import pytest

SCRIPT = "/home/user/buggy_export.py"
DB = "/home/user/backups.db"
OUTPUT = "/home/user/fixed_metrics.json"
TRACE = "/tmp/export_sql_trace.txt"


def run_export():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing or is not a file."
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    if os.path.exists(TRACE):
        os.remove(TRACE)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/sql_instrument" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["TRACE_SQL"] = TRACE
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Running {SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    run_export()


def load_output():
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return json.load(f)


def test_fixed_metrics_json_exists():
    json_path = "/home/user/fixed_metrics.json"
    assert os.path.exists(json_path), f"Output file {json_path} is missing. Did you run the script?"
    assert os.path.isfile(json_path), f"Path {json_path} is not a file."


def test_fixed_metrics_json_content():
    json_path = "/home/user/fixed_metrics.json"
    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected JSON root to be a list, but got {type(data).__name__}."
    assert len(data) == 4, f"Expected 4 records in the JSON output, but found {len(data)}."

    expected_data = [
        {"id": 1, "job_name": "DB_PROD_FULL", "size": 1000, "running_total": 1000},
        {"id": 2, "job_name": "DB_PROD_INC_1", "size": 100, "running_total": 1100},
        {"id": 3, "job_name": "DB_PROD_INC_2", "size": 150, "running_total": 1250},
        {"id": 4, "job_name": "DB_PROD_INC_3", "size": 120, "running_total": 1370}
    ]

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Record at index {i} is not a dictionary."

        expected_keys = {"id", "job_name", "size", "running_total"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Record at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        assert actual["id"] == expected["id"], f"Record at index {i}: Expected id {expected['id']}, got {actual['id']}."
        assert actual["job_name"] == expected["job_name"], f"Record at index {i}: Expected job_name '{expected['job_name']}', got '{actual['job_name']}'."
        assert actual["size"] == expected["size"], f"Record at index {i}: Expected size {expected['size']}, got {actual['size']}."
        assert actual["running_total"] == expected["running_total"], f"Record at index {i}: Expected running_total {expected['running_total']}, got {actual['running_total']}."


def test_executed_recursive_query_keeps_window_function():
    assert os.path.isfile(TRACE), "The export script did not execute any traceable SQLite query."
    trace = open(TRACE, "r", encoding="utf-8").read()
    statements = trace.split("---STATEMENT---")

    def is_required_query(sql):
        return (
            re.search(r"\bWITH\s+RECURSIVE\b", sql, re.I) and
            re.search(r"\bbackup_chain\b", sql, re.I) and
            re.search(r"\bbackup_deps\b", sql, re.I) and
            re.search(r"\bSUM\s*\(", sql, re.I) and
            re.search(r"\bOVER\s*\(", sql, re.I) and
            re.search(r"\bORDER\s+BY\s+(?:\w+\.)?created_at\b", sql, re.I)
        )

    assert any(is_required_query(sql) for sql in statements), (
        "The script must actually execute a WITH RECURSIVE backup_chain query that "
        "uses backup_deps and retains SUM(...) OVER (ORDER BY created_at)."
    )


def test_export_follows_changed_branching_dependency_graph():
    backup = "/tmp/backups.db.original"
    shutil.copy2(DB, backup)
    try:
        token = secrets.token_hex(5)
        sizes = {i: 20 + secrets.randbelow(900) for i in range(1, 10)}
        branch_id = 100 + secrets.randbelow(100000)
        deep_id = branch_id + 1
        unrelated_id = branch_id + 2

        conn = sqlite3.connect(DB)
        try:
            for row_id in range(1, 7):
                conn.execute("UPDATE backups SET size = ? WHERE id = ?", (sizes[row_id], row_id))
            conn.execute("UPDATE backups SET job_name = ? WHERE id = 2", ("CHANGED_INC_" + token,))
            conn.execute(
                "INSERT INTO backups(id, job_name, size, created_at) VALUES (?, ?, ?, ?)",
                (branch_id, "BRANCH_" + token, sizes[7], "2023-01-02 06:00:00"),
            )
            conn.execute(
                "INSERT INTO backups(id, job_name, size, created_at) VALUES (?, ?, ?, ?)",
                (deep_id, "DEEP_" + token, sizes[8], "2023-01-05 00:00:00"),
            )
            conn.execute(
                "INSERT INTO backups(id, job_name, size, created_at) VALUES (?, ?, ?, ?)",
                (unrelated_id, "UNRELATED_" + token, sizes[9], "2023-01-03 12:00:00"),
            )
            conn.execute("INSERT INTO backup_deps(backup_id, depends_on) VALUES (?, 2)", (branch_id,))
            conn.execute("INSERT INTO backup_deps(backup_id, depends_on) VALUES (?, ?)", (deep_id, branch_id))
            conn.execute("INSERT INTO backup_deps(backup_id, depends_on) VALUES (?, 5)", (unrelated_id,))
            conn.commit()

            rows = {
                row[0]: {"id": row[0], "job_name": row[1], "size": row[2], "created_at": row[3]}
                for row in conn.execute("SELECT id, job_name, size, created_at FROM backups")
            }
            root = conn.execute("SELECT id FROM backups WHERE job_name = 'DB_PROD_FULL'").fetchone()[0]
            children = {}
            for child, parent in conn.execute("SELECT backup_id, depends_on FROM backup_deps"):
                children.setdefault(parent, []).append(child)
        finally:
            conn.close()

        descendants = set()
        pending = [root]
        while pending:
            node = pending.pop()
            if node in descendants:
                continue
            descendants.add(node)
            pending.extend(children.get(node, []))

        ordered = sorted((rows[i] for i in descendants), key=lambda row: (row["created_at"], row["id"]))
        expected = []
        running = 0
        for row in ordered:
            running += row["size"]
            expected.append({
                "id": row["id"],
                "job_name": row["job_name"],
                "size": row["size"],
                "running_total": running,
            })

        run_export()
        actual = load_output()
        assert actual == expected, "The executed script did not derive the export from the changed dependency graph and sizes."
        for record in actual:
            assert set(record) == {"id", "job_name", "size", "running_total"}
            assert type(record["id"]) is int
            assert type(record["job_name"]) is str
            assert type(record["size"]) is int
            assert type(record["running_total"]) is int
        assert all(record["id"] != unrelated_id for record in actual), "An unrelated backup was included."
    finally:
        shutil.copy2(backup, DB)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
