#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'LAUNCHER_EOF' > /tmp/run_audit_graph.py
import json
import re
import runpy
import sqlite3

SCRIPT_PATH = "/home/user/audit_graph.py"
LOG_PATH = "/tmp/audit_query_log.json"
real_connect = sqlite3.connect
executed_sql = []


def normalize(sql):
    return re.sub(r"\s+", " ", sql.lower()).strip()


def inspect_sql(sql):
    if not isinstance(sql, str):
        return
    normalized = normalize(sql)
    if "communications" in normalized and "select" in normalized:
        if not re.search(r"\bnot\s+indexed\b", normalized):
            raise RuntimeError("communications was queried without NOT INDEXED")
        executed_sql.append(sql)


class TrackedCursor:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, *args, **kwargs):
        inspect_sql(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        inspect_sql(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        inspect_sql(sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class TrackedConnection:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return TrackedCursor(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        inspect_sql(sql)
        return TrackedCursor(self._connection.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        inspect_sql(sql)
        return TrackedCursor(self._connection.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        inspect_sql(sql)
        return TrackedCursor(self._connection.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def tracked_connect(database, *args, **kwargs):
    return TrackedConnection(real_connect(database, *args, **kwargs))


sqlite3.connect = tracked_connect
try:
    runpy.run_path(SCRIPT_PATH, run_name="__main__")
finally:
    with open(LOG_PATH, "w") as f:
        json.dump(executed_sql, f)
LAUNCHER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess

import networkx as nx
import pytest

SCRIPT_PATH = "/home/user/audit_graph.py"
OUTPUT_PATH = "/home/user/central_actors.json"
QUERY_LOG_PATH = "/tmp/audit_query_log.json"
DB_PATH = "/home/user/audit.db"


def compute_expected():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT sender_id, receiver_id FROM communications NOT INDEXED"
        ).fetchall()
    finally:
        conn.close()

    graph = nx.DiGraph()
    graph.add_edges_from(rows)
    centralities = nx.in_degree_centrality(graph)
    top_three = sorted(
        centralities.items(), key=lambda item: item[1], reverse=True
    )[:3]
    return [
        {"employee_id": employee_id, "centrality": round(value, 4)}
        for employee_id, value in top_three
    ]


EXPECTED = compute_expected()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    if os.path.exists(QUERY_LOG_PATH):
        os.remove(QUERY_LOG_PATH)

    result = subprocess.run(
        ["python3", "/tmp/run_audit_graph.py"],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Submitted script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_output():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")


def test_script_exists_and_bypasses_index():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read().lower()
    assert "not indexed" in content, "The script does not seem to bypass the index using 'NOT INDEXED'."

    assert os.path.exists(QUERY_LOG_PATH), "No SQL execution log was produced."
    with open(QUERY_LOG_PATH, "r") as f:
        queries = json.load(f)
    assert queries, "The script did not execute a SELECT on communications using NOT INDEXED."
    assert any(
        "sender_id" in q.lower()
        and "receiver_id" in q.lower()
        and re.search(r"\bnot\s+indexed\b", q.lower())
        for q in queries
    ), "The executed communications query did not retrieve sender_id and receiver_id using NOT INDEXED."


def test_output_json_exists_and_format():
    data = load_output()
    assert isinstance(data, list), "JSON output should be a list."
    assert len(data) == 3, f"Expected exactly 3 items in the JSON output, found {len(data)}."

    for item in data:
        assert "employee_id" in item, "Missing 'employee_id' in JSON output."
        assert "centrality" in item, "Missing 'centrality' in JSON output."
        assert isinstance(item["centrality"], (int, float)), "Centrality must be a number."


def test_output_json_correct_actors():
    data = load_output()
    employee_ids = [item["employee_id"] for item in data]
    expected_ids = ["EMP999", "EMP888", "EMP777"]
    assert employee_ids == expected_ids, f"Expected top 3 actors to be {expected_ids}, but got {employee_ids}."


def test_output_matches_database_centralities():
    data = load_output()
    assert data == EXPECTED, f"Expected database-derived results {EXPECTED}, but got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
