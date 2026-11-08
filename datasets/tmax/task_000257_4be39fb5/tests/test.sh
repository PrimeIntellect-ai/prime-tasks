#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_etl_instrumented.py
import json
import runpy
import sqlite3 as real_sqlite3
import sys
import types

TRACE = "/tmp/etl_sql_trace.jsonl"

def record(sql):
    if isinstance(sql, str):
        with open(TRACE, "a") as f:
            f.write(json.dumps(sql) + "\n")

class CursorWrapper:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, *args, **kwargs):
        record(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        record(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        record(sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionWrapper:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorWrapper(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        record(sql)
        return CursorWrapper(self._connection.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        record(sql)
        return CursorWrapper(self._connection.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        record(sql)
        return CursorWrapper(self._connection.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

proxy = types.ModuleType("sqlite3")
for name in dir(real_sqlite3):
    setattr(proxy, name, getattr(real_sqlite3, name))

def connect(*args, **kwargs):
    return ConnectionWrapper(real_sqlite3.connect(*args, **kwargs))

proxy.connect = connect
sys.modules["sqlite3"] = proxy
runpy.run_path("/home/user/process_etl.py", run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import copy
import json
import os
import random
import re
import sqlite3
import subprocess
from datetime import datetime, timedelta

import jsonschema

SCRIPT = "/home/user/process_etl.py"
OUTPUT = "/home/user/transformed_events.jsonl"
SCHEMA = "/home/user/schema.json"
DB = "/home/user/telemetry.db"
TRACE = "/tmp/etl_sql_trace.jsonl"
RUNNER = "/tmp/run_etl_instrumented.py"


def read_records():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    records = []
    with open(OUTPUT, "r") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def expected_records(schema):
    conn = sqlite3.connect(DB)
    rows = conn.execute("""
        SELECT id, uid, action, created_at
        FROM activity_logs
        ORDER BY uid, created_at
    """).fetchall()
    conn.close()

    previous = {}
    expected = []
    for event_id, uid, action, created_at in rows:
        diff = None
        if uid in previous:
            try:
                current = datetime.strptime(created_at, "%Y-%m-%d %H:%M:%S")
                prior = datetime.strptime(previous[uid], "%Y-%m-%d %H:%M:%S")
                diff = int((current - prior).total_seconds())
            except ValueError:
                pass
        previous[uid] = created_at

        if action == "checkout":
            record = {
                "user_id": uid,
                "event_id": event_id,
                "timestamp": created_at,
                "seconds_since_last_event": diff,
            }
            try:
                jsonschema.validate(instance=record, schema=schema)
            except jsonschema.ValidationError:
                continue
            expected.append(record)
    return sorted(expected, key=lambda r: r["event_id"])


def run_script_and_require_window_query():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    if os.path.exists(TRACE):
        os.remove(TRACE)

    result = subprocess.run(
        ["python3", RUNNER],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "process_etl.py did not run successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The script did not create transformed_events.jsonl."
    assert os.path.isfile(TRACE), "The script did not execute any SQLite statements."

    with open(TRACE, "r") as f:
        statements = [json.loads(line) for line in f if line.strip()]
    assert any(re.search(r"\bOVER\b", sql, re.IGNORECASE) for sql in statements), (
        "No executed SQL statement used an OVER clause; the calculation must use "
        "a SQL window function."
    )


def test_script_requirements_and_execution():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file."

    with open(SCRIPT, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imports_jsonschema = any(
        (isinstance(node, ast.Import) and any(alias.name == "jsonschema" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "jsonschema")
        for node in ast.walk(tree)
    )
    validation_call = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Name) and node.func.id in {"validate", "is_valid", "iter_errors"})
            or (isinstance(node.func, ast.Attribute) and node.func.attr in {"validate", "is_valid", "iter_errors"})
        )
        for node in ast.walk(tree)
    )
    assert imports_jsonschema, "process_etl.py must import the jsonschema library."
    assert validation_call, "process_etl.py must call jsonschema validation before writing records."

    with open(SCHEMA, "r") as f:
        original_schema = json.load(f)

    conn = sqlite3.connect(DB)
    max_id = conn.execute("SELECT COALESCE(MAX(id), 0) FROM activity_logs").fetchone()[0]
    max_uid = conn.execute(
        "SELECT COALESCE(MAX(uid), 1000) FROM activity_logs WHERE typeof(uid) = 'integer'"
    ).fetchone()[0]
    uid_base = max_uid + random.randint(10000, 1000000)
    start = datetime(2040, 1, 1) + timedelta(seconds=random.randint(0, 10000000))
    stamp = lambda seconds: (start + timedelta(seconds=seconds)).strftime("%Y-%m-%d %H:%M:%S")

    injected = [
        (max_id + 1, uid_base, "login", stamp(0)),
        (max_id + 2, uid_base, "view_item", stamp(41)),
        (max_id + 3, uid_base, "checkout", stamp(178)),
        (max_id + 4, uid_base + 1, "checkout", stamp(300)),
        (max_id + 5, uid_base + 2, "login", stamp(400)),
        (max_id + 6, uid_base + 2, "checkout", stamp(499)),
    ]
    conn.executemany("INSERT INTO activity_logs VALUES (?, ?, ?, ?)", injected)
    conn.commit()
    conn.close()

    # Temporarily make one otherwise-valid checkout fail the supplied schema. This
    # verifies that the script actually reads and applies schema.json rather than
    # merely hard-coding the known bad UID case.
    restrictive_schema = copy.deepcopy(original_schema)
    restrictive_schema["properties"]["event_id"] = {
        "type": "integer",
        "not": {"const": max_id + 6},
    }

    try:
        with open(SCHEMA, "w") as f:
            json.dump(restrictive_schema, f)
        run_script_and_require_window_query()
        actual = sorted(read_records(), key=lambda r: r.get("event_id", 0))
        assert actual == expected_records(restrictive_schema), (
            "The script did not correctly process runtime database rows and discard "
            "records rejected by the supplied JSON schema."
        )
    finally:
        with open(SCHEMA, "w") as f:
            json.dump(original_schema, f, indent=2)

    # Leave the required final artifact generated against the original schema.
    run_script_and_require_window_query()


def test_transformed_events_exists():
    output_path = "/home/user/transformed_events.jsonl"
    assert os.path.exists(output_path), f"Output file {output_path} is missing."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."


def test_transformed_events_content():
    output_path = "/home/user/transformed_events.jsonl"
    assert os.path.exists(output_path), "Output file is missing."

    with open(output_path, "r") as f:
        lines = f.read().strip().splitlines()

    actual_records = []
    for line in lines:
        if not line.strip():
            continue
        try:
            actual_records.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Output file contains invalid JSON line: {line}"

    # Derive expected records directly from the database
    db_path = "/home/user/telemetry.db"
    assert os.path.exists(db_path), "Database file missing."

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
        SELECT id, uid, action, created_at
        FROM activity_logs
        ORDER BY uid, created_at
    """)
    rows = cur.fetchall()
    conn.close()

    user_prev_time = {}
    expected_records_list = []

    for row in rows:
        event_id, uid, action, created_at = row

        diff = None
        if uid in user_prev_time:
            fmt = '%Y-%m-%d %H:%M:%S'
            try:
                t1 = datetime.strptime(created_at, fmt)
                t2 = datetime.strptime(user_prev_time[uid], fmt)
                diff = int((t1 - t2).total_seconds())
            except ValueError:
                pass

        user_prev_time[uid] = created_at

        if action == 'checkout':
            if not isinstance(uid, int):
                continue

            expected_records_list.append({
                "user_id": uid,
                "event_id": event_id,
                "timestamp": created_at,
                "seconds_since_last_event": diff
            })

    def sort_key(r):
        return r.get("event_id", 0)

    actual_records.sort(key=sort_key)
    expected_records_list.sort(key=sort_key)

    assert len(actual_records) == len(expected_records_list), (
        f"Expected {len(expected_records_list)} valid checkout records, "
        f"but got {len(actual_records)} in the output file."
    )

    for actual, expected in zip(actual_records, expected_records_list):
        assert actual == expected, (
            f"Record mismatch.\nExpected: {expected}\nActual: {actual}\n"
            "Ensure that you are calculating the time difference correctly using Window functions, "
            "and that invalid records are discarded based on the JSON schema."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
