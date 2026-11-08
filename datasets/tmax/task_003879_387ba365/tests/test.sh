#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
import uuid

DB_PATH = "/home/user/backup_metadata.db"
SCRIPT_PATH = "/home/user/analyze_backups.py"
PLAN_PATH = "/home/user/plan.txt"
CSV_PATH = "/home/user/anomalies.csv"
RUNNER_PATH = "/tmp/run_analyze_with_trace.py"

RUNNER_SOURCE = r'''
import json
import runpy
import sqlite3 as real_sqlite3
import sys
import types

script_path, trace_path = sys.argv[1], sys.argv[2]
trace = []

def safe_params(value):
    if value is None or isinstance(value, (str, int, float, bytes)):
        return value.decode("latin1") if isinstance(value, bytes) else value
    if isinstance(value, dict):
        return {str(k): safe_params(v) for k, v in value.items()}
    try:
        return [safe_params(v) for v in value]
    except TypeError:
        return repr(value)

def record(sql, params=()):
    trace.append({"sql": str(sql), "params": safe_params(params)})

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor
    def execute(self, sql, parameters=()):
        record(sql, parameters)
        self._cursor.execute(sql, parameters)
        return self
    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        for parameters in values:
            record(sql, parameters)
        self._cursor.executemany(sql, values)
        return self
    def executescript(self, sql_script):
        record(sql_script, ())
        self._cursor.executescript(sql_script)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __enter__(self):
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
    def execute(self, sql, parameters=()):
        record(sql, parameters)
        return CursorProxy(self._connection.execute(sql, parameters))
    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        for parameters in values:
            record(sql, parameters)
        return CursorProxy(self._connection.executemany(sql, values))
    def executescript(self, sql_script):
        record(sql_script, ())
        return CursorProxy(self._connection.executescript(sql_script))
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    return ConnectionProxy(real_sqlite3.connect(*args, **kwargs))

shim = types.ModuleType("sqlite3")
for attr in dir(real_sqlite3):
    setattr(shim, attr, getattr(real_sqlite3, attr))
shim.connect = connect
sys.modules["sqlite3"] = shim
sys.argv = [script_path]
exit_code = 0
try:
    runpy.run_path(script_path, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        exit_code = int(exc.code) if isinstance(exc.code, int) else 1
except BaseException:
    exit_code = 1
    raise
finally:
    with open(trace_path, "w", encoding="utf-8") as f:
        json.dump(trace, f)
sys.exit(exit_code)
'''


def custom_indexes(conn):
    return conn.execute("""
        SELECT name, sql
        FROM sqlite_master
        WHERE type='index' AND tbl_name='backup_logs'
          AND name NOT LIKE 'sqlite_autoindex%'
        ORDER BY name
    """).fetchall()


def drop_custom_indexes():
    with sqlite3.connect(DB_PATH) as conn:
        for name, _ in custom_indexes(conn):
            conn.execute('DROP INDEX "' + name.replace('"', '""') + '"')


def data_snapshot():
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute("""
            SELECT id, server_name, backup_timestamp, status,
                   backup_size_bytes, duration_seconds
            FROM backup_logs ORDER BY id
        """).fetchall()


def expected_anomalies():
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute("""
            SELECT server_name, backup_timestamp, backup_size_bytes, id
            FROM backup_logs
            WHERE status = 'SUCCESS'
        """).fetchall()

    grouped = {}
    for server, timestamp, size, row_id in rows:
        grouped.setdefault(server, []).append((timestamp, row_id, size))

    expected = {}
    for server, backups in grouped.items():
        backups.sort(key=lambda row: (row[0], row[1]), reverse=True)
        recent = backups[:3]
        latest = recent[0][2]
        average = sum(row[2] for row in recent) / len(recent)
        if latest > 1.5 * average:
            expected[server] = (float(latest), round(average, 2))
    return expected


def read_csv_results():
    assert os.path.exists(CSV_PATH), f"Anomalies CSV missing at {CSV_PATH}"
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert len(rows) >= 1, "The anomalies.csv file must contain a header row."
    expected_header = ['server_name', 'latest_size', 'avg_recent_size']
    assert rows[0] == expected_header, f"Expected header {expected_header}, but got {rows[0]}"
    data_rows = [row for row in rows[1:] if row]
    result = {}
    for row in data_rows:
        assert len(row) == 3, f"CSV row must have exactly three columns: {row}"
        assert row[0] not in result, f"Duplicate anomaly row for {row[0]}"
        result[row[0]] = (float(row[1]), float(row[2]))
    return result


def assert_csv_matches_database():
    expected = expected_anomalies()
    actual = read_csv_results()
    assert set(actual) == set(expected), \
        f"Expected anomaly servers {sorted(expected)}, got {sorted(actual)}"
    for server, (expected_latest, expected_average) in expected.items():
        actual_latest, actual_average = actual[server]
        assert actual_latest == expected_latest, \
            f"Wrong latest_size for {server}: {actual_latest} != {expected_latest}"
        assert math.isclose(actual_average, expected_average, rel_tol=1e-9, abs_tol=0.011), \
            f"Wrong avg_recent_size for {server}: {actual_average} != {expected_average}"


def assert_index_strategy():
    with sqlite3.connect(DB_PATH) as conn:
        indexes = custom_indexes(conn)
        assert len(indexes) > 0, "No custom index was created on the backup_logs table."
        assert len(indexes) == 1, f"Expected a single custom index, found {[x[0] for x in indexes]}"
        name, create_sql = indexes[0]
        columns = [row[2].lower() for row in conn.execute(
            'PRAGMA index_info("' + name.replace('"', '""') + '")'
        )]
    assert 'server_name' in columns, "Index must include server_name."
    assert 'backup_timestamp' in columns, "Index must include backup_timestamp."
    sql_upper = (create_sql or '').upper()
    assert 'STATUS' in [c.upper() for c in columns] or re.search(
        r"\bWHERE\b[\s\S]*\bSTATUS\b[\s\S]*SUCCESS", sql_upper
    ), "Index must optimize filtering successful backups, either by status or a SUCCESS partial predicate."
    return name


def assert_trace_and_plan(trace, index_name):
    sql_entries = [entry.get('sql', '') for entry in trace]
    assert any(re.search(r"\bPRAGMA\s+(?:TABLE_INFO|TABLE_XINFO)\b", sql, re.I) or
               re.search(r"\bSQLITE_MASTER\b|\bSQLITE_SCHEMA\b", sql, re.I)
               for sql in sql_entries), \
        "The script did not perform schema discovery with PRAGMA or SQLite schema metadata."

    create_count = sum(len(re.findall(r"\bCREATE\s+(?:UNIQUE\s+)?INDEX\b", sql, re.I))
                       for sql in sql_entries)
    assert create_count == 1, f"Expected exactly one executed CREATE INDEX statement, got {create_count}."

    explain_entries = [entry for entry in trace
                       if re.match(r"^\s*EXPLAIN\s+QUERY\s+PLAN\b", entry.get('sql', ''), re.I)]
    assert explain_entries, "The script did not execute EXPLAIN QUERY PLAN."

    actual_window_queries = [sql for sql in sql_entries
        if not re.match(r"^\s*EXPLAIN\b", sql, re.I)
        and re.search(r"\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\([^)]*\)\s*OVER\s*\(", sql, re.I | re.S)]
    assert actual_window_queries, \
        "No executed anomaly query used a ranking window function to identify recent backups."

    assert os.path.exists(PLAN_PATH), f"Execution plan output missing at {PLAN_PATH}"
    with open(PLAN_PATH, encoding="utf-8") as f:
        plan_content = f.read()
    plan_upper = plan_content.upper()
    assert "USING INDEX" in plan_upper or "USING COVERING INDEX" in plan_upper, \
        "The execution plan in plan.txt does not indicate that an index was used."
    assert index_name.upper() in plan_upper, \
        "plan.txt does not identify the custom index created by the script."

    entry = explain_entries[-1]
    params = entry.get('params', [])
    with sqlite3.connect(DB_PATH) as conn:
        computed_plan = conn.execute(entry['sql'], params).fetchall()
    assert computed_plan, "EXPLAIN QUERY PLAN returned no rows."
    for row in computed_plan:
        detail = str(row[3])
        assert detail in plan_content, \
            f"plan.txt is not the actual exported plan; missing detail: {detail}"


def run_submission(tag):
    drop_custom_indexes()
    for path in (PLAN_PATH, CSV_PATH):
        if os.path.lexists(path):
            os.remove(path)
    before = data_snapshot()
    trace_path = f"/tmp/analyze_trace_{tag}.json"
    with open(RUNNER_PATH, "w", encoding="utf-8") as f:
        f.write(RUNNER_SOURCE)
    completed = subprocess.run(
        [sys.executable, RUNNER_PATH, SCRIPT_PATH, trace_path],
        cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert completed.returncode == 0, \
        f"analyze_backups.py failed:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert data_snapshot() == before, "The script modified existing backup log data."
    with open(trace_path, encoding="utf-8") as f:
        trace = json.load(f)
    index_name = assert_index_strategy()
    assert_trace_and_plan(trace, index_name)
    assert_csv_matches_database()


def test_complete_workflow_and_dynamic_input():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Expected a file at {SCRIPT_PATH}"

    run_submission("original")
    original = read_csv_results()
    assert "db-server-04" in original, "Expected db-server-04 to be reported as anomalous."
    assert original["db-server-04"][0] == 100000000
    assert math.isclose(original["db-server-04"][1], 46666666.67, rel_tol=1e-5)

    token = uuid.uuid4().hex
    anomalous_server = "verifier-anomaly-" + token
    ordinary_server = "verifier-ordinary-" + token
    with sqlite3.connect(DB_PATH) as conn:
        conn.executemany("""
            INSERT INTO backup_logs
                (server_name, backup_timestamp, status, backup_size_bytes, duration_seconds)
            VALUES (?, ?, ?, ?, ?)
        """, [
            (anomalous_server, '2099-01-01T00:00:00', 'SUCCESS', 11000000, 1),
            (anomalous_server, '2099-01-02T00:00:00', 'SUCCESS', 13000000, 1),
            (anomalous_server, '2099-01-03T00:00:00', 'SUCCESS', 97000000, 1),
            (anomalous_server, '2099-01-04T00:00:00', 'FAILED', 999000000, 1),
            (ordinary_server, '2099-02-01T00:00:00', 'SUCCESS', 20000000, 1),
            (ordinary_server, '2099-02-02T00:00:00', 'SUCCESS', 21000000, 1),
            (ordinary_server, '2099-02-03T00:00:00', 'SUCCESS', 22000000, 1),
        ])

    run_submission("perturbed")
    perturbed = read_csv_results()
    assert anomalous_server in perturbed, "The script did not detect the verifier-added anomaly."
    assert ordinary_server not in perturbed, "The script incorrectly reported a non-anomalous server."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
