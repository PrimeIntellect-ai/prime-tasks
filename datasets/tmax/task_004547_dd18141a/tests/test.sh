#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
from collections import deque

import pytest

ANALYZE = "/home/user/analyze.py"
GRAPH = "/home/user/job_graph.json"
DB = "/home/user/backups.db"
REPORT = "/home/user/report.json"
TRACE = "/tmp/analyze_sql_trace.log"
WRAPPER_DIR = "/tmp/sqlite_trace_wrapper"


def install_sqlite_trace_wrapper():
    package = os.path.join(WRAPPER_DIR, "sqlite3")
    os.makedirs(package, exist_ok=True)
    wrapper = r'''
import datetime
import os
import time
import _sqlite3 as _db
from _sqlite3 import *

Date = datetime.date
Time = datetime.time
Timestamp = datetime.datetime
Binary = memoryview
DateFromTicks = lambda ticks: Date(*time.localtime(ticks)[:3])
TimeFromTicks = lambda ticks: Time(*time.localtime(ticks)[3:6])
TimestampFromTicks = lambda ticks: Timestamp(*time.localtime(ticks)[:6])

class TracedConnection(_db.Connection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._user_trace_callback = None
        _db.Connection.set_trace_callback(self, self._record_trace)

    def _record_trace(self, statement):
        path = os.environ.get("ANALYZE_SQL_TRACE")
        if path:
            with open(path, "a", encoding="utf-8") as trace_file:
                trace_file.write(statement.replace("\\n", " ") + "\\n")
        if self._user_trace_callback is not None:
            self._user_trace_callback(statement)

    def set_trace_callback(self, callback):
        self._user_trace_callback = callback
        _db.Connection.set_trace_callback(self, self._record_trace)


def connect(*args, **kwargs):
    args = list(args)
    if len(args) >= 6:
        args[5] = TracedConnection
    else:
        kwargs["factory"] = TracedConnection
    return _db.connect(*args, **kwargs)
'''
    with open(os.path.join(package, "__init__.py"), "w", encoding="utf-8") as f:
        f.write(wrapper)


def run_analyze():
    install_sqlite_trace_wrapper()
    if os.path.exists(TRACE):
        os.unlink(TRACE)
    env = os.environ.copy()
    env["ANALYZE_SQL_TRACE"] = TRACE
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = WRAPPER_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")
    result = subprocess.run(
        ["python3", ANALYZE],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return open(TRACE, encoding="utf-8").read() if os.path.exists(TRACE) else ""


def assert_required_sql_was_executed(trace):
    sql = re.sub(r'["`\[\]]', '', trace.lower())
    assert re.search(r"json_extract\s*\(", sql), (
        "analyze.py must execute SQLite SQL using JSON extraction functions."
    )
    window = re.search(
        r"avg\s*\([^)]*\)\s*over\s*\([^)]*partition\s+by\s+[^)]*job_id"
        r"[^)]*order\s+by\s+[^)]*run_date[^)]*rows\s+between\s+2\s+preceding"
        r"\s+and\s+current\s+row[^)]*\)",
        sql,
        re.S,
    )
    assert window is not None, (
        "analyze.py must execute AVG() as a window function partitioned by job_id, "
        "ordered by run_date, with the current row and two preceding rows."
    )


def test_analyze_exists_runs_and_executes_required_sql():
    assert os.path.isfile(ANALYZE), f"File {ANALYZE} is missing or is not a regular file."
    trace = run_analyze()
    assert_required_sql_was_executed(trace)


def test_report_json_exists_and_correct():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not valid JSON.")

    assert isinstance(report_data, list), "Report must be a JSON array."

    expected_data = [
        {
            "job_id": "JOB_START",
            "storage_target": "s3",
            "latest_3run_avg": 110.0
        },
        {
            "job_id": "JOB_A",
            "storage_target": "gcs",
            "latest_3run_avg": 70.0
        },
        {
            "job_id": "JOB_C",
            "storage_target": "s3",
            "latest_3run_avg": 300.0
        },
        {
            "job_id": "JOB_END",
            "storage_target": "local",
            "latest_3run_avg": 15.0
        }
    ]

    assert len(report_data) == len(expected_data), f"Expected {len(expected_data)} items in report, found {len(report_data)}."

    for i, (actual, expected) in enumerate(zip(report_data, expected_data)):
        assert actual.get("job_id") == expected["job_id"], f"Item {i}: Expected job_id {expected['job_id']}, got {actual.get('job_id')}"
        assert actual.get("storage_target") == expected["storage_target"], f"Item {i}: Expected storage_target {expected['storage_target']}, got {actual.get('storage_target')}"
        assert abs(actual.get("latest_3run_avg", 0) - expected["latest_3run_avg"]) < 1e-5, f"Item {i}: Expected latest_3run_avg {expected['latest_3run_avg']}, got {actual.get('latest_3run_avg')}"


def shortest_path(graph, start, end):
    queue = deque([[start]])
    seen = {start}
    while queue:
        path = queue.popleft()
        node = path[-1]
        if node == end:
            return path
        for child in graph.get(node, []):
            if child not in seen:
                seen.add(child)
                queue.append(path + [child])
    raise AssertionError("Dynamic fixture unexpectedly has no path")


def test_analyze_handles_changed_graph_and_database():
    graph_original = open(GRAPH, "rb").read()
    db_original = open(DB, "rb").read()
    report_original = open(REPORT, "rb").read() if os.path.exists(REPORT) else None

    graph = {
        "JOB_START": ["JOB_B", "JOB_A"],
        "JOB_B": ["JOB_E"],
        "JOB_E": ["JOB_END"],
        "JOB_A": ["JOB_C"],
        "JOB_C": ["JOB_F"],
        "JOB_F": ["JOB_END"],
        "JOB_END": [],
    }
    jobs = list(graph)
    targets = {job: "target_" + secrets.token_hex(7) for job in jobs}
    durations = {}
    for position, job in enumerate(jobs):
        base = 40 + position * 37 + secrets.randbelow(19)
        durations[job] = [base + 9, base - 4, base + 25, base + 2]

    try:
        with open(GRAPH, "w", encoding="utf-8") as f:
            json.dump(graph, f)

        os.unlink(DB)
        conn = sqlite3.connect(DB)
        conn.execute("CREATE TABLE backup_logs (id INTEGER PRIMARY KEY, job_id TEXT, run_date TEXT, duration_seconds INTEGER)")
        conn.execute("CREATE TABLE job_configs (job_id TEXT PRIMARY KEY, config_json TEXT)")
        dates = ["2041-02-03", "2041-02-01", "2041-02-04", "2041-02-02"]
        for job in jobs:
            conn.execute(
                "INSERT INTO job_configs(job_id, config_json) VALUES (?, ?)",
                (job, json.dumps({"storage_target": targets[job], "nonce": secrets.token_hex(5)})),
            )
            for date, duration in zip(dates, durations[job]):
                conn.execute(
                    "INSERT INTO backup_logs(job_id, run_date, duration_seconds) VALUES (?, ?, ?)",
                    (job, date, duration),
                )
        conn.commit()
        conn.close()

        trace = run_analyze()
        assert_required_sql_was_executed(trace)

        with open(REPORT, encoding="utf-8") as f:
            actual = json.load(f)
        path = shortest_path(graph, "JOB_START", "JOB_END")
        expected = []
        for job in path:
            ordered = sorted(zip(dates, durations[job]))
            latest_three = [value for _, value in ordered[-3:]]
            expected.append({
                "job_id": job,
                "storage_target": targets[job],
                "latest_3run_avg": sum(latest_three) / 3.0,
            })

        assert isinstance(actual, list), "Dynamic report must be a JSON array."
        assert len(actual) == len(expected), "Dynamic report has the wrong path length."
        for i, (got, wanted) in enumerate(zip(actual, expected)):
            assert set(got) == {"job_id", "storage_target", "latest_3run_avg"}, f"Item {i} has the wrong structure."
            assert got["job_id"] == wanted["job_id"], f"Item {i} is not in shortest-path order."
            assert got["storage_target"] == wanted["storage_target"], f"Item {i} has the wrong JSON-extracted target."
            assert abs(got["latest_3run_avg"] - wanted["latest_3run_avg"]) < 1e-5, f"Item {i} has the wrong latest moving average."
    finally:
        with open(GRAPH, "wb") as f:
            f.write(graph_original)
        with open(DB, "wb") as f:
            f.write(db_original)
        if report_original is None:
            if os.path.exists(REPORT):
                os.unlink(REPORT)
        else:
            with open(REPORT, "wb") as f:
                f.write(report_original)


def test_optimize_sql_exists_and_correct():
    optimize_path = "/home/user/optimize.sql"
    assert os.path.exists(optimize_path), f"File {optimize_path} is missing."

    with open(optimize_path, "r") as f:
        sql_content = f.read().strip().lower()

    # The index should be on backup_logs(job_id, run_date) or backup_logs(run_date, job_id)
    # We will use regex to check for CREATE INDEX ... ON backup_logs ... (job_id, run_date)
    assert "create " in sql_content and "index " in sql_content, "optimize.sql must contain a CREATE INDEX statement."
    assert "on backup_logs" in sql_content, "The index must be created on the backup_logs table."

    # Check for the columns in the index
    match = re.search(r"\(([^)]+)\)", sql_content)
    assert match is not None, "Could not find column definitions in CREATE INDEX statement."

    columns = [c.strip() for c in match.group(1).split(",")]
    assert "job_id" in columns and "run_date" in columns, "The index must include both job_id and run_date columns."

    with tempfile.TemporaryDirectory() as tempdir:
        copied_db = os.path.join(tempdir, "backups.db")
        shutil.copy2(DB, copied_db)
        conn = sqlite3.connect(copied_db)
        before = {row[1] for row in conn.execute("PRAGMA index_list('backup_logs')")}
        try:
            conn.executescript(open(optimize_path, encoding="utf-8").read())
        except sqlite3.Error as exc:
            pytest.fail(f"optimize.sql is not executable SQLite SQL: {exc}")

        after_rows = list(conn.execute("PRAGMA index_list('backup_logs')"))
        new_names = [row[1] for row in after_rows if row[1] not in before]
        assert new_names, "optimize.sql did not create an index on backup_logs."

        suitable = False
        for name in new_names:
            escaped = name.replace("'", "''")
            info = list(conn.execute(f"PRAGMA index_info('{escaped}')"))
            indexed_columns = [row[2].lower() if isinstance(row[2], str) else row[2] for row in info]
            if indexed_columns[:2] == ["job_id", "run_date"]:
                suitable = True
                break
        conn.close()
        assert suitable, (
            "At least one created backup_logs index must begin with (job_id, run_date) "
            "to support partitioning by job_id and ordering by run_date."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
