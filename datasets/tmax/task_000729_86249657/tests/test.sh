#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import json
import subprocess
import sys
import pytest

DB_PATH = "/home/user/backups.db"
SCRIPT_PATH = "/home/user/analyze_graph.py"
REPORT_PATH = "/home/user/pagerank_report.json"


def compute_pagerank(edges, alpha=0.85, max_iter=100, tol=1.0e-6):
    """
    Computes PageRank using the same default algorithm as NetworkX.
    """
    nodes = set()
    out_degree = {}
    for u, v in edges:
        nodes.add(u)
        nodes.add(v)
        out_degree[u] = out_degree.get(u, 0) + 1
        if v not in out_degree:
            out_degree[v] = 0

    N = len(nodes)
    if N == 0:
        return {}

    pr = {n: 1.0 / N for n in nodes}

    for _ in range(max_iter):
        prev_pr = pr.copy()
        dangling_sum = sum(prev_pr[n] for n in nodes if out_degree[n] == 0)

        for n in nodes:
            pr[n] = (1.0 - alpha) / N + alpha * (dangling_sum / N)

        for u, v in edges:
            pr[v] += alpha * prev_pr[u] / out_degree[u]

        err = sum(abs(pr[n] - prev_pr[n]) for n in nodes)
        if err < N * tol:
            break

    return pr


def test_analyze_script_exists_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} does not exist or is not a regular file."

    # Add fresh active data and an inactive trap so a precomputed report cannot pass.
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM job_dependencies WHERE source_job IN (?, ?)", ("verifier_job_G", "verifier_inactive_X"))
    c.execute("INSERT INTO job_dependencies VALUES (?, ?, ?)", ("verifier_job_G", "job_A", 1))
    c.execute("INSERT INTO job_dependencies VALUES (?, ?, ?)", ("verifier_inactive_X", "verifier_inactive_Y", 0))
    conn.commit()
    conn.close()

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    launcher = r'''
import re
import runpy
import sqlite3
import networkx

query_ok = False
pagerank_ok = False
_sentinel = object()
_original_connect = sqlite3.connect
_original_pagerank = networkx.pagerank


def record_query(sql, parameters):
    global query_ok
    if not isinstance(sql, str) or not re.search(r"\\bis_active\\s*=\\s*\\?", sql, re.IGNORECASE):
        return
    if parameters is _sentinel:
        return
    try:
        values = list(parameters.values()) if isinstance(parameters, dict) else list(parameters)
    except TypeError:
        values = [parameters]
    if any(value == 1 for value in values):
        query_ok = True


class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=_sentinel):
        record_query(sql, parameters)
        if parameters is _sentinel:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, parameters):
        return self._cursor.executemany(sql, parameters)

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_sentinel):
        record_query(sql, parameters)
        if parameters is _sentinel:
            cursor = self._connection.execute(sql)
        else:
            cursor = self._connection.execute(sql, parameters)
        return CursorProxy(cursor)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def checked_connect(*args, **kwargs):
    return ConnectionProxy(_original_connect(*args, **kwargs))


def checked_pagerank(*args, **kwargs):
    global pagerank_ok
    pagerank_ok = True
    return _original_pagerank(*args, **kwargs)


sqlite3.connect = checked_connect
networkx.pagerank = checked_pagerank

try:
    runpy.run_path("/home/user/analyze_graph.py", run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise

assert query_ok, "Script did not execute a parameterized query using 'is_active = ?' with parameter 1."
assert pagerank_ok, "Script did not call networkx.pagerank()."
'''
    launcher_path = "/tmp/run_analyze_checked.py"
    with open(launcher_path, "w") as f:
        f.write(launcher)

    result = subprocess.run(
        [sys.executable, launcher_path],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_graph.py failed verification (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), "Running analyze_graph.py did not generate the report."


def test_pagerank_report_exists_and_valid():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report file is not valid JSON.")

    assert isinstance(report, dict), "Root of JSON must be an object."
    assert "pagerank_scores" in report, "Root object must have a single key 'pagerank_scores'."
    assert len(report) == 1, "Root object must have exactly one key."

    scores = report["pagerank_scores"]
    assert isinstance(scores, list), "'pagerank_scores' must be a list."


def test_pagerank_report_values():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        report = json.load(f)
    scores = report.get("pagerank_scores", [])

    # Retrieve active edges from DB
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT source_job, target_job FROM job_dependencies WHERE is_active = 1")
    edges = c.fetchall()
    conn.close()

    # Compute expected PageRank
    pr = compute_pagerank(edges)
    expected_results = [{"job": k, "score": round(v, 4)} for k, v in pr.items()]
    expected_results.sort(key=lambda x: (-x["score"], x["job"]))

    assert len(scores) == len(expected_results), f"Expected {len(expected_results)} scores, found {len(scores)}."

    for i, (actual, expected) in enumerate(zip(scores, expected_results)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary."
        assert set(actual.keys()) == {"job", "score"}, f"Item at index {i} must have exactly 'job' and 'score' keys."

        assert isinstance(actual["job"], str), f"'job' at index {i} must be a string."
        assert isinstance(actual["score"], float), f"'score' at index {i} must be a float."

        assert actual["job"] == expected["job"], f"Expected job '{expected['job']}' at index {i}, found '{actual.get('job')}'."
        assert actual["score"] == expected["score"], f"Expected score {expected['score']} for job '{expected['job']}', found {actual.get('score')}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
