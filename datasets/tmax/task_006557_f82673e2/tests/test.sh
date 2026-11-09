#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HARNESS_EOF' > /tmp/run_instrumented.py
import json
import os
import runpy
import sqlite3
import sys

script_path = sys.argv[1]
relationship = sys.argv[2]
log_path = sys.argv[3]
sys.argv = [script_path, relationship]

real_connect = sqlite3.connect
events = []

def contains_relationship(value):
    if isinstance(value, str):
        return value == relationship
    if isinstance(value, dict):
        return any(contains_relationship(v) for v in value.values())
    if isinstance(value, (list, tuple, set)):
        return any(contains_relationship(v) for v in value)
    return False

def record(method, sql, args, kwargs):
    params = args[0] if args else kwargs.get("parameters")
    events.append({
        "kind": "sql",
        "method": method,
        "sql": sql if isinstance(sql, str) else repr(sql),
        "has_parameters": bool(args) or "parameters" in kwargs,
        "binds_relationship": contains_relationship(params),
    })

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

    def __iter__(self):
        return iter(self._cursor)

    def __enter__(self):
        self._cursor.__enter__()
        return self

    def __exit__(self, *args):
        return self._cursor.__exit__(*args)

    def execute(self, sql, *args, **kwargs):
        record("execute", sql, args, kwargs)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        record("executemany", sql, args, kwargs)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql):
        record("executescript", sql, (), {})
        self._cursor.executescript(sql)
        return self

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        record("execute", sql, args, kwargs)
        return CursorProxy(self._connection.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        record("executemany", sql, args, kwargs)
        return CursorProxy(self._connection.executemany(sql, *args, **kwargs))

    def executescript(self, sql):
        record("executescript", sql, (), {})
        return CursorProxy(self._connection.executescript(sql))

def traced_connect(database, *args, **kwargs):
    events.append({"kind": "connect", "database": os.fspath(database)})
    return ConnectionProxy(real_connect(database, *args, **kwargs))

sqlite3.connect = traced_connect
try:
    runpy.run_path(script_path, run_name="__main__")
finally:
    with open(log_path, "w") as f:
        json.dump(events, f)
HARNESS_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import uuid
import pytest

SCRIPT_PATH = "/home/user/find_triangles.py"
OUTPUT_PATH = "/home/user/triangles.json"
DB_PATH = "/home/user/graph_data.db"
HARNESS_PATH = "/tmp/run_instrumented.py"
TRACE_PATH = "/tmp/find_triangles_trace.json"

def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {OUTPUT_PATH} does not contain valid JSON.")

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

def test_script_execution_knows():
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "KNOWS"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed to execute with 'KNOWS'. Error: {result.stderr}"
    data = load_output()
    assert isinstance(data, list), "Output JSON must be a list of arrays."
    sorted_data = sorted([sorted(triangle) for triangle in data])
    assert sorted_data == [[1, 2, 3]], f"Expected [[1, 2, 3]] for 'KNOWS', got {data}"

def test_script_execution_likes():
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "LIKES"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed to execute with 'LIKES'. Error: {result.stderr}"
    data = load_output()
    assert isinstance(data, list), "Output JSON must be a list of arrays."
    sorted_data = sorted([sorted(triangle) for triangle in data])
    assert sorted_data == [[4, 5, 6]], f"Expected [[4, 5, 6]] for 'LIKES', got {data}"

def test_parameterized_query_used():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    has_qmark = "?" in content
    has_named = ":" in content
    assert has_qmark or has_named, "Script does not appear to use parameterized queries (missing '?' or ':name' placeholders)."

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"Script contains syntax errors: {e}")

    parameterized_execute = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"execute", "executemany"}
        and (len(node.args) >= 2 or any(k.arg == "parameters" for k in node.keywords))
        for node in ast.walk(tree)
    )
    assert parameterized_execute, "No SQL execute call supplies a separate parameters argument."

def test_randomized_relationship_and_runtime_binding():
    backup = "/tmp/graph_data_verifier_backup.db"
    shutil.copy2(DB_PATH, backup)
    relationship = "AUDIT_" + uuid.uuid4().hex + "' OR type <> '"

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            used = {row[0] for row in conn.execute("SELECT id FROM vertices")}
            ids = []
            while len(ids) < 6:
                candidate = 100000 + secrets.randbelow(900000000)
                if candidate not in used:
                    used.add(candidate)
                    ids.append(candidate)

            conn.executemany(
                "INSERT INTO vertices(id, label) VALUES (?, ?)",
                [(node_id, "Audit") for node_id in ids]
            )
            edges = [
                (ids[0], ids[1], relationship),
                (ids[1], ids[2], relationship),
                (ids[2], ids[0], relationship),
                (ids[3], ids[4], relationship),
                (ids[4], ids[5], relationship),
                (ids[5], ids[3], relationship),
                (ids[0], ids[3], relationship),
            ]
            conn.executemany(
                "INSERT INTO connections(source, target, type) VALUES (?, ?, ?)", edges
            )
            conn.commit()

            rows = conn.execute(
                "SELECT e1.source, e1.target, e2.target "
                "FROM connections e1 "
                "JOIN connections e2 ON e1.target = e2.source "
                "JOIN connections e3 ON e2.target = e3.source AND e3.target = e1.source "
                "WHERE e1.type = ? AND e2.type = ? AND e3.type = ?",
                (relationship, relationship, relationship),
            ).fetchall()
            expected = sorted({tuple(sorted(row)) for row in rows})
        finally:
            conn.close()

        if os.path.exists(TRACE_PATH):
            os.remove(TRACE_PATH)
        result = subprocess.run(
            ["python3", HARNESS_PATH, SCRIPT_PATH, relationship, TRACE_PATH],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Script failed for a randomized relationship: {result.stderr}"

        data = load_output()
        assert isinstance(data, list), "Output JSON must be a list."
        assert all(isinstance(t, list) and len(t) == 3 for t in data), "Every triangle must be a three-item array."
        assert all(all(isinstance(v, int) and not isinstance(v, bool) for v in t) for t in data), "Node IDs must be integers."
        assert all(t == sorted(t) for t in data), "Every triangle must be sorted in ascending numerical order."
        assert len({tuple(t) for t in data}) == len(data), "Output contains duplicate triangles."
        assert sorted(tuple(t) for t in data) == expected, f"Incorrect randomized result: expected {expected}, got {data}"

        assert os.path.isfile(TRACE_PATH), "Runtime SQL trace was not produced."
        with open(TRACE_PATH, "r") as f:
            events = json.load(f)

        connects = [e for e in events if e.get("kind") == "connect"]
        assert any(os.path.abspath(e["database"]) == DB_PATH for e in connects), "Script did not connect to /home/user/graph_data.db."

        sql_events = [e for e in events if e.get("kind") == "sql"]
        bound_queries = [
            e for e in sql_events
            if e.get("has_parameters")
            and e.get("binds_relationship")
            and "connections" in e.get("sql", "").lower()
        ]
        assert bound_queries, "No executed query against connections bound the relationship as a separate parameter."
        assert not any(relationship in e.get("sql", "") for e in sql_events), "The relationship was interpolated directly into SQL text."
    finally:
        shutil.copy2(backup, DB_PATH)
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
