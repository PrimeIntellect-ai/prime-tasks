#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import gc
import importlib.util
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
import sys
import tempfile
import tracemalloc

import pytest

SERVICE = "/home/user/service"


def load_source_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_leak_report_contents():
    report_path = "/home/user/service/leak_report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 non-empty lines in {report_path}, found {len(lines)}."
    assert lines[0] == "_decode_cache", f"Line 1 in {report_path} is incorrect."
    assert lines[1] == "SELECT id, metadata FROM records", f"Line 2 in {report_path} is incorrect."


def test_serializer_fixed():
    pyc_path = "/home/user/service/serializer.pyc"
    py_path = "/home/user/service/serializer.py"

    assert not os.path.exists(pyc_path), f"The compiled bytecode file {pyc_path} should have been deleted."
    assert os.path.isfile(py_path), f"The fixed source file {py_path} is missing."

    with open(py_path, "r") as f:
        content = f.read()

    assert "_decode_cache" not in content, "The fixed serializer.py still contains the _decode_cache variable."
    assert "def deserialize(" in content, "The fixed serializer.py is missing the deserialize function."


def test_serializer_behavior_and_no_retained_decode_cache():
    serializer = load_source_module(
        "submitted_serializer_behavior_test",
        os.path.join(SERVICE, "serializer.py"),
    )
    assert callable(getattr(serializer, "deserialize", None))

    cases = [
        {"user_id": random.randrange(10000, 10000000), "action": secrets.token_hex(9)},
        {"nested": {"items": [1, None, True, "héllo", {"k": "v"}]}, "n": -3.25},
        [secrets.token_hex(4), 12, False, {"random": secrets.token_urlsafe(12)}],
    ]
    for value in cases:
        raw = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        payload = base64.b64encode(raw)
        assert serializer.deserialize(payload) == value
        assert serializer.deserialize(payload.decode("ascii")) == value

    # Deserialization must produce fresh data rather than returning a cached mutable object.
    value = {"user_id": random.randrange(10000000, 20000000), "items": [1, 2, 3]}
    payload = base64.b64encode(json.dumps(value).encode("utf-8"))
    first = serializer.deserialize(payload)
    first["items"].append("mutation")
    second = serializer.deserialize(payload)
    assert second == value
    assert first is not second

    # Unique large streaming records expose the original unbounded payload/result cache.
    del first, second, value, payload
    gc.collect()
    tracemalloc.start()
    for i in range(500):
        token = secrets.token_hex(16)
        expected = {"sequence": i, "token": token, "body": "x" * 32768}
        raw = json.dumps(expected, separators=(",", ":")).encode("utf-8")
        payload = base64.b64encode(raw)
        result = serializer.deserialize(payload)
        assert result == expected
    del token, expected, raw, payload, result
    gc.collect()
    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert current < 3 * 1024 * 1024, (
        f"deserialize retained {current / 1024 / 1024:.2f} MiB after unique inputs; "
        "decoded payloads appear to be cached"
    )


def test_query_engine_fixed():
    file_path = "/home/user/service/query_engine.py"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    assert "SELECT id, metadata FROM records" not in content, "The flawed query is still present in query_engine.py."
    assert "fetchall()" not in content, "The fetchall() call is still present in query_engine.py."
    assert "?" in content or "%s" in content or "WHERE id" in content, "The query does not appear to be parameterized or filtered."


def test_query_engine_behavior_and_database_filtering():
    fd, db_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    real_connect = sqlite3.connect
    ids = random.sample(range(10000, 10000000), 180)
    expected = {}
    conn = real_connect(db_path)
    conn.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, metadata TEXT)")
    for record_id in ids:
        metadata = json.dumps({"marker": secrets.token_hex(12), "id": record_id})
        expected[record_id] = metadata
        conn.execute("INSERT INTO records (id, metadata) VALUES (?, ?)", (record_id, metadata))
    conn.commit()
    conn.close()

    executions = []
    fetchall_used = []

    class CursorProxy:
        def __init__(self, inner):
            self._inner = inner

        def execute(self, sql, parameters=()):
            executions.append((sql, parameters))
            self._inner.execute(sql, parameters)
            return self

        def fetchall(self):
            fetchall_used.append(True)
            return self._inner.fetchall()

        def __iter__(self):
            return iter(self._inner)

        def __getattr__(self, name):
            return getattr(self._inner, name)

    class ConnectionProxy:
        def __init__(self, inner):
            self._inner = inner

        def cursor(self, *args, **kwargs):
            return CursorProxy(self._inner.cursor(*args, **kwargs))

        def execute(self, sql, parameters=()):
            executions.append((sql, parameters))
            return CursorProxy(self._inner.execute(sql, parameters))

        def __enter__(self):
            self._inner.__enter__()
            return self

        def __exit__(self, *args):
            return self._inner.__exit__(*args)

        def __getattr__(self, name):
            return getattr(self._inner, name)

    def monitored_connect(*args, **kwargs):
        return ConnectionProxy(real_connect(*args, **kwargs))

    sqlite3.connect = monitored_connect
    try:
        query_engine = load_source_module(
            "submitted_query_engine_behavior_test",
            os.path.join(SERVICE, "query_engine.py"),
        )
        chosen = random.sample(ids, 5)
        missing = max(ids) + random.randrange(1000, 100000)
        for record_id in chosen:
            executions.clear()
            assert query_engine.get_record_metadata(db_path, record_id) == expected[record_id]
            assert_filtered_metadata_query(executions, record_id)
        executions.clear()
        assert query_engine.get_record_metadata(db_path, missing) is None
        assert_filtered_metadata_query(executions, missing)
        assert not fetchall_used, "get_record_metadata fetched an entire result set"
    finally:
        sqlite3.connect = real_connect
        os.unlink(db_path)


def assert_filtered_metadata_query(executions, requested_id):
    selects = [(sql, params) for sql, params in executions if re.match(r"^\s*select\b", str(sql), re.I)]
    assert selects, "get_record_metadata did not execute a SELECT query"
    assert len(selects) == 1, "get_record_metadata should need only one SELECT query"
    sql, params = selects[0]
    match = re.match(
        r'^\s*select\s+(.*?)\s+from\s+(?:["`\[]?records["`\]]?)\b(.*)$',
        str(sql),
        re.I | re.S,
    )
    assert match, f"Unexpected records query: {sql!r}"
    projection = re.sub(r'[\s"`\[\]]', '', match.group(1)).lower()
    assert projection in ("metadata", "records.metadata"), (
        f"Query must fetch only metadata, not extra columns: {sql!r}"
    )
    tail = match.group(2)
    assert re.search(r'\bwhere\b', tail, re.I), f"Query is not filtered in SQL: {sql!r}"
    assert re.search(r'(?:\brecords\s*\.\s*)?["`\[]?id["`\]]?\s*=\s*', tail, re.I), (
        f"Query must filter by exact record id: {sql!r}"
    )
    if "?" in str(sql) or re.search(r"[:@$][A-Za-z_]", str(sql)):
        values = params.values() if isinstance(params, dict) else params
        assert requested_id in values, "The requested record_id was not bound to the SQL query"


def test_main_execution_and_output():
    result = subprocess.run(
        [sys.executable, "/home/user/service/main.py", "--run"],
        cwd="/home/user/service",
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"main.py failed to run successfully. Output: {result.stdout}\nErrors: {result.stderr}"
    assert "Success" in result.stdout, "main.py did not print 'Success', indicating memory limits may have been exceeded."

    output_path = "/home/user/service/output.json"
    assert os.path.isfile(output_path), f"The file {output_path} was not generated."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    assert len(data) == 3, f"Expected 3 items in output.json, found {len(data)}."

    expected_data = [
        {"user_id": 1, "action": "login", "metadata": {"status": "active", "tier": "premium"}},
        {"user_id": 2, "action": "logout", "metadata": {"status": "inactive", "tier": "free"}},
        {"user_id": 3, "action": "update", "metadata": {"status": "active", "tier": "standard"}}
    ]

    assert data == expected_data, f"The contents of {output_path} do not match the expected transformed data."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
