#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

SCRIPT = "/home/user/analyze.py"
DB = "/home/user/metrics.db"
OUTPUT = "/home/user/output.json"


def expected_rows(endpoint, limit, offset):
    conn = sqlite3.connect(DB)
    rows = conn.execute(
        "SELECT id, endpoint, response_time_ms, timestamp "
        "FROM api_requests WHERE endpoint = ? ORDER BY timestamp ASC, id ASC",
        (endpoint,),
    ).fetchall()
    conn.close()

    result = []
    previous = None
    for row_id, row_endpoint, response_time, timestamp in rows:
        result.append({
            "id": row_id,
            "endpoint": row_endpoint,
            "response_time_ms": response_time,
            "timestamp": timestamp,
            "prev_response_time_ms": previous,
            "time_diff": None if previous is None else response_time - previous,
        })
        previous = response_time
    result.sort(key=lambda row: (row["timestamp"], row["id"]), reverse=True)
    return result[offset:offset + limit]


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file missing at {OUTPUT} after running the script."
    with open(OUTPUT, "r") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")


def assert_rows(actual, expected):
    assert isinstance(actual, list), "Output JSON should be a list of objects."
    assert len(actual) == len(expected), f"Expected {len(expected)} results, got {len(actual)}."
    for i, (actual_row, expected_row) in enumerate(zip(actual, expected)):
        assert actual_row.get("id") == expected_row["id"], f"Row {i} id mismatch."
        assert actual_row.get("endpoint") == expected_row["endpoint"], f"Row {i} endpoint mismatch."
        assert actual_row.get("response_time_ms") == expected_row["response_time_ms"], f"Row {i} response_time_ms mismatch."
        assert actual_row.get("timestamp") == expected_row["timestamp"], f"Row {i} timestamp mismatch."
        assert actual_row.get("prev_response_time_ms") == expected_row["prev_response_time_ms"], f"Row {i} prev_response_time_ms mismatch."
        if expected_row["time_diff"] is None:
            assert actual_row.get("time_diff") is None, f"Row {i} time_diff mismatch. Expected None."
        else:
            assert actual_row.get("time_diff") is not None, f"Row {i} time_diff unexpectedly null."
            assert abs(actual_row["time_diff"] - expected_row["time_diff"]) < 1e-5, f"Row {i} time_diff mismatch."


def test_analyze_script_exists():
    assert os.path.isfile(SCRIPT), "The script /home/user/analyze.py does not exist."


def test_script_execution_and_output():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT, "/api/checkout", "5", "2"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"

    data = read_output()
    assert isinstance(data, list), "Output JSON should be a list of objects."

    conn = sqlite3.connect(DB)
    rows = conn.execute(
        "SELECT id, endpoint, response_time_ms, timestamp FROM api_requests "
        "WHERE endpoint = ? ORDER BY timestamp ASC",
        ("/api/checkout",),
    ).fetchall()
    conn.close()

    expected = []
    prev_time = None
    for row_id, endpoint, resp_time, ts in rows:
        expected.append({
            "id": row_id,
            "endpoint": endpoint,
            "response_time_ms": resp_time,
            "timestamp": ts,
            "prev_response_time_ms": prev_time,
            "time_diff": resp_time - prev_time if prev_time is not None else None,
        })
        prev_time = resp_time
    expected.sort(key=lambda row: row["timestamp"], reverse=True)
    assert_rows(data, expected[2:7])


def make_instrumentation(directory):
    code = r'''
import json
import os
import sqlite3

TRACE = os.environ.get("ANALYZE_TRACE")
_real_connect = sqlite3.connect

def emit(event):
    if TRACE:
        with open(TRACE, "a") as handle:
            handle.write(json.dumps(event, default=repr) + "\\n")

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)
    def execute(self, sql, parameters=()):
        emit({"kind": "sql", "sql": sql, "params": parameters})
        self._cursor.execute(sql, parameters)
        return self
    def executemany(self, sql, parameters):
        emit({"kind": "executemany", "sql": sql, "params": parameters})
        self._cursor.executemany(sql, parameters)
        return self
    def executescript(self, sql):
        emit({"kind": "executescript", "sql": sql})
        self._cursor.executescript(sql)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)
    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, parameters=()):
        emit({"kind": "sql", "sql": sql, "params": parameters})
        return CursorProxy(self._connection.execute(sql, parameters))
    def executemany(self, sql, parameters):
        emit({"kind": "executemany", "sql": sql, "params": parameters})
        return CursorProxy(self._connection.executemany(sql, parameters))
    def executescript(self, sql):
        emit({"kind": "executescript", "sql": sql})
        return CursorProxy(self._connection.executescript(sql))
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)
    def __setattr__(self, name, value):
        if name == "_connection":
            object.__setattr__(self, name, value)
        else:
            setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect

try:
    import jsonschema
    _top_validate = jsonschema.validate
    def traced_validate(instance, schema, *args, **kwargs):
        emit({"kind": "validation", "instance": instance, "schema": schema})
        return _top_validate(instance, schema, *args, **kwargs)
    jsonschema.validate = traced_validate

    for _name in list(dir(jsonschema)):
        _cls = getattr(jsonschema, _name, None)
        if isinstance(_cls, type) and _name.startswith("Draft") and hasattr(_cls, "validate"):
            _original = _cls.validate
            def make_validate(original):
                def wrapped(self, instance, *args, **kwargs):
                    emit({"kind": "validation", "instance": instance, "schema": getattr(self, "schema", None)})
                    return original(self, instance, *args, **kwargs)
                return wrapped
            try:
                setattr(_cls, "validate", make_validate(_original))
            except Exception:
                pass
except Exception:
    pass
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w") as handle:
        handle.write(code)


def create_dynamic_database(endpoint_a, endpoint_b):
    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)
    conn.execute("CREATE TABLE api_requests (id INTEGER PRIMARY KEY, endpoint TEXT, response_time_ms REAL, timestamp DATETIME)")
    base = datetime(2025, 2, 3, 9, 0, 0)
    endpoints = [endpoint_a, "/noise", endpoint_b, endpoint_a, endpoint_b, "/noise", endpoint_a,
                 endpoint_b, endpoint_a, endpoint_b, endpoint_a, endpoint_b, endpoint_a, "/noise"]
    token = secrets.randbelow(5000) + 1000
    for index, endpoint in enumerate(endpoints):
        response = float(token + index * 17 + (index % 3) * 0.25)
        timestamp = (base + timedelta(seconds=index * 43)).strftime("%Y-%m-%d %H:%M:%S")
        conn.execute(
            "INSERT INTO api_requests(endpoint, response_time_ms, timestamp) VALUES (?, ?, ?)",
            (endpoint, response, timestamp),
        )
    conn.commit()
    conn.close()


def assert_trace(trace_path, endpoint, limit, offset, output):
    with open(trace_path) as handle:
        events = [json.loads(line) for line in handle if line.strip()]

    sql_events = [event for event in events if event.get("kind") in {"sql", "executemany", "executescript"}]
    assert len(sql_events) == 1, "The script must execute exactly one SQL query."
    assert sql_events[0]["kind"] == "sql", "The analytics must be performed by one parameterized query."

    event = sql_events[0]
    sql = event.get("sql", "")
    assert isinstance(sql, str)
    assert re.search(r"\bLAG\s*\(", sql, re.I), "SQL query must use LAG()."
    assert re.search(r"\bOVER\b", sql, re.I), "SQL query must use a window function."
    assert re.search(r"\bprev_response_time_ms\b", sql, re.I), "SQL must produce prev_response_time_ms."
    assert re.search(r"\btime_diff\b", sql, re.I) and "-" in sql, "SQL must compute time_diff."
    assert re.search(r"ORDER\s+BY[\s\S]*timestamp[\s\S]*DESC", sql, re.I), "Final results must be ordered by timestamp descending."
    assert re.search(r"LIMIT\s+(?:\?|[:@$][A-Za-z_]\w*)", sql, re.I), "LIMIT must be parameterized."
    assert re.search(r"OFFSET\s+(?:\?|[:@$][A-Za-z_]\w*)", sql, re.I), "OFFSET must be parameterized."

    params = event.get("params")
    if isinstance(params, dict):
        values = list(params.values())
    elif isinstance(params, list):
        values = params
    else:
        values = []
    assert endpoint in values, "Endpoint must be supplied as a SQL parameter."
    assert limit in values, "Limit must be supplied as a SQL parameter."
    assert offset in values, "Offset must be supplied as a SQL parameter."

    validations = [event for event in events if event.get("kind") == "validation"]
    matching = [event for event in validations if event.get("instance") == output]
    assert matching, "The resulting list must be validated using jsonschema."
    schema = matching[-1].get("schema")
    assert isinstance(schema, dict) and schema.get("type") == "array"
    items = schema.get("items", {})
    required = {"id", "endpoint", "response_time_ms", "timestamp", "prev_response_time_ms", "time_diff"}
    assert required.issubset(set(items.get("required", []))), "The required output schema was not used."
    properties = items.get("properties", {})
    assert properties.get("id", {}).get("type") == "integer"
    assert properties.get("endpoint", {}).get("type") == "string"
    assert properties.get("response_time_ms", {}).get("type") == "number"
    assert properties.get("timestamp", {}).get("type") == "string"
    assert set(properties.get("prev_response_time_ms", {}).get("type", [])) == {"number", "null"}
    assert set(properties.get("time_diff", {}).get("type", [])) == {"number", "null"}


def test_parameterized_database_side_analytics_and_schema_validation():
    backup = tempfile.mktemp(prefix="metrics-backup-", suffix=".db")
    shutil.copy2(DB, backup)
    instrumentation = tempfile.mkdtemp(prefix="analyze-instrument-")
    make_instrumentation(instrumentation)

    endpoint_a = "/dynamic/" + secrets.token_hex(8)
    endpoint_b = "x' OR 1=1 -- " + secrets.token_hex(6)
    try:
        create_dynamic_database(endpoint_a, endpoint_b)
        scenarios = [
            (endpoint_a, 3, 0),
            (endpoint_a, 2, 2),
            (endpoint_b, 4, 1),
            ("/missing/" + secrets.token_hex(5), 5, 0),
        ]
        for index, (endpoint, limit, offset) in enumerate(scenarios):
            trace = os.path.join(instrumentation, f"trace-{index}.jsonl")
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            env = os.environ.copy()
            env["ANALYZE_TRACE"] = trace
            env["PYTHONPATH"] = instrumentation + os.pathsep + env.get("PYTHONPATH", "")
            result = subprocess.run(
                ["python3", SCRIPT, endpoint, str(limit), str(offset)],
                capture_output=True,
                text=True,
                env=env,
            )
            assert result.returncode == 0, f"Dynamic invocation failed:\n{result.stderr}"
            output = read_output()
            expected = expected_rows(endpoint, limit, offset)
            assert_rows(output, expected)
            assert output == expected, "Output contains missing or unexpected fields or values."
            assert_trace(trace, endpoint, limit, offset, output)
    finally:
        shutil.copy2(backup, DB)
        os.remove(backup)
        shutil.rmtree(instrumentation, ignore_errors=True)
        subprocess.run(["python3", SCRIPT, "/api/checkout", "5", "2"], check=True)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
