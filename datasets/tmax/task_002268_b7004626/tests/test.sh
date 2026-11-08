#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/analyze_deadlocks.py"
REPORT_PATH = "/home/user/deadlock_report.json"
DB_PATH = "/home/user/deadlocks.db"


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"


def test_script_uses_parameterized_query():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "?" in content or re.search(r":\w+", content), \
        "Script does not appear to use parameterized queries ('?' or named parameters)."
    assert ".execute" in content, "Script does not call .execute() on a cursor."


def load_report():
    assert os.path.exists(REPORT_PATH), \
        f"Report file missing at {REPORT_PATH}. The script must generate this file."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report file is not valid JSON")


def test_script_execution_and_output():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    cmd = [
        sys.executable, SCRIPT_PATH,
        "--start-tx", "T1",
        "--min-total-wait", "500",
        "--limit", "2",
        "--offset", "1",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    data = load_report()
    expected_data = [
        {"path": ["T1", "T4", "T5", "T1"], "total_wait": 700},
        {"path": ["T1", "T2", "T3", "T1"], "total_wait": 600},
    ]
    assert data == expected_data, \
        f"JSON output does not match expected results.\nExpected: {expected_data}\nGot: {data}"


def expected_cycles(rows, start, minimum, limit, offset):
    found = []
    for s1, b, w1 in rows:
        if s1 != start:
            continue
        for s2, c, w2 in rows:
            if s2 != b:
                continue
            for s3, end, w3 in rows:
                if s3 == c and end == start:
                    found.append({
                        "path": [start, b, c, start],
                        "total_wait": w1 + w2 + w3,
                    })
    found = [x for x in found if x["total_wait"] >= minimum]
    found.sort(key=lambda x: (-x["total_wait"], x["path"][1], x["path"][2]))
    return found[offset:offset + limit]


def make_instrumentation(directory):
    sitecustomize = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_log_path = os.environ.get("TRACE_SQL_PATH")


def _jsonable(value):
    if isinstance(value, dict):
        return {str(k): _jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return repr(value)


def _write(entry):
    if _log_path:
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")


def _plan(conn, sql, params, supplied):
    text = sql.lstrip()
    if not (text[:6].upper() == "SELECT" or text[:4].upper() == "WITH"):
        return []
    try:
        cur = conn.cursor()
        if supplied:
            cur.execute("EXPLAIN QUERY PLAN " + sql, params)
        else:
            cur.execute("EXPLAIN QUERY PLAN " + sql)
        return [list(row) for row in cur.fetchall()]
    except Exception as exc:
        return [["plan-error", repr(exc)]]


class CursorProxy:
    def __init__(self, cursor, conn):
        self._cursor = cursor
        self._conn = conn

    def execute(self, sql, params=None):
        supplied = params is not None
        plan = _plan(self._conn, sql, params, supplied)
        _write({"kind": "execute", "sql": sql,
                "params": _jsonable(params) if supplied else None,
                "plan": plan})
        if supplied:
            self._cursor.execute(sql, params)
        else:
            self._cursor.execute(sql)
        return self

    def executemany(self, sql, seq):
        values = list(seq)
        _write({"kind": "executemany", "sql": sql, "params": _jsonable(values), "plan": []})
        self._cursor.executemany(sql, values)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class ConnectionProxy:
    def __init__(self, conn):
        self._conn = conn

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._conn.cursor(*args, **kwargs), self._conn)

    def execute(self, sql, params=None):
        cur = CursorProxy(self._conn.cursor(), self._conn)
        return cur.execute(sql, params)

    def executemany(self, sql, seq):
        cur = CursorProxy(self._conn.cursor(), self._conn)
        return cur.executemany(sql, seq)

    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, *args):
        return self._conn.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._conn, name)


def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)


def strip_sql_comments(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql


def parameter_values(params):
    if isinstance(params, dict):
        return list(params.values())
    if isinstance(params, list):
        return params
    return []


def assert_single_matching_query(trace_path, start, minimum, limit, offset):
    with open(trace_path, "r") as f:
        entries = [json.loads(line) for line in f if line.strip()]

    assert len(entries) == 1, \
        f"Expected exactly one executed SQL statement, but observed {len(entries)}: {entries}"
    entry = entries[0]
    assert entry["kind"] == "execute", "The required query must be executed once with execute()."

    sql = strip_sql_comments(entry["sql"])
    upper = sql.upper()
    assert upper.lstrip().startswith(("SELECT", "WITH")), "The executed statement is not a SELECT query."
    assert re.search(r"\bWAIT_GRAPH\b", upper), "The executed query does not read wait_graph."
    assert "SRC_TX" in upper and "DST_TX" in upper and "WAIT_TIME_MS" in upper, \
        "The executed query does not perform the required graph matching and wait calculation."
    assert "ORDER BY" in upper, "Sorting must be performed by the SQL query."
    assert re.search(r"\bLIMIT\b", upper), "Pagination LIMIT must be performed by SQL."
    assert re.search(r"\bOFFSET\b", upper), "Pagination OFFSET must be performed by SQL."
    assert re.search(r"\bWHERE\b|\bHAVING\b", upper), "Filtering must be performed by SQL."
    assert "?" in sql or re.search(r":\w+", sql), "The executed query is not parameterized."

    values = parameter_values(entry.get("params"))
    for value in (start, minimum, limit, offset):
        assert value in values, f"Argument {value!r} was not supplied as a bound SQL parameter."

    # A genuine three-edge match produces at least three table access operations in
    # SQLite's query plan. This rejects an executed dummy query plus Python-side matching.
    plan_details = " ".join(str(row[-1]) for row in entry.get("plan", [])).upper()
    accesses = re.findall(r"\b(?:SCAN|SEARCH)\b", plan_details)
    assert len(accesses) >= 3, \
        f"Query plan does not perform a three-edge graph match: {entry.get('plan')}"
    assert "ORDER BY" in plan_details, \
        f"Query plan does not perform the required ordering: {entry.get('plan')}"


def test_generated_database_multiple_argument_combinations():
    token = uuid.uuid4().hex[:10]
    a = "A_" + token
    other = "O'Reilly_" + token
    absent = "missing_" + token
    b1, b2, b3 = "b1_" + token, "b2_" + token, "b3_" + token
    c1, c2, c3 = "c1_" + token, "c2_" + token, "c3_" + token
    x1, x2 = "x1_" + token, "x2_" + token

    rows = [
        (a, b2, 111), (b2, c2, 222), (c2, a, 333),
        (a, b1, 250), (b1, c3, 200), (c3, a, 216),
        (a, b3, 700), (b3, c1, 300), (c1, a, 201),
        (a, x1, 5), (x1, x2, 6), (x2, a, 7),
        (other, c1, 401), (c1, b1, 402), (b1, other, 403),
        (other, c2, 90), (c2, b3, 80), (b3, other, 70),
        ("noise_" + token, a, 999), (x2, other, 1),
    ]
    cases = [
        (a, 0, 20, 0),
        (a, 600, 2, 1),
        (a, 1200, 5, 0),
        (other, 200, 1, 1),
        (absent, 0, 4, 0),
    ]

    backup = tempfile.NamedTemporaryFile(delete=False)
    backup.close()
    shutil.copy2(DB_PATH, backup.name)
    instrument_dir = tempfile.mkdtemp(prefix="sqltrace_")
    make_instrumentation(instrument_dir)

    try:
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        conn.execute("CREATE TABLE wait_graph(src_tx TEXT, dst_tx TEXT, wait_time_ms INTEGER)")
        conn.executemany("INSERT INTO wait_graph VALUES (?, ?, ?)", rows)
        conn.commit()
        conn.close()

        for index, (start, minimum, limit, offset) in enumerate(cases):
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
            trace_path = os.path.join(instrument_dir, f"trace_{index}.jsonl")
            env = os.environ.copy()
            env["TRACE_SQL_PATH"] = trace_path
            env["PYTHONPATH"] = instrument_dir + os.pathsep + env.get("PYTHONPATH", "")
            cmd = [
                sys.executable, SCRIPT_PATH,
                "--start-tx", start,
                "--min-total-wait", str(minimum),
                "--limit", str(limit),
                "--offset", str(offset),
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, env=env)
            assert result.returncode == 0, \
                f"Script failed for generated case {index}. stderr: {result.stderr}"
            actual = load_report()
            expected = expected_cycles(rows, start, minimum, limit, offset)
            assert actual == expected, \
                f"Wrong generated-case output.\nExpected: {expected}\nGot: {actual}"
            assert_single_matching_query(trace_path, start, minimum, limit, offset)

        conn = sqlite3.connect(DB_PATH)
        current_rows = conn.execute("SELECT src_tx, dst_tx, wait_time_ms FROM wait_graph").fetchall()
        conn.close()
        assert sorted(current_rows) == sorted(rows), "The script modified the database."
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup.name, DB_PATH)
        os.unlink(backup.name)
        shutil.rmtree(instrument_dir, ignore_errors=True)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
