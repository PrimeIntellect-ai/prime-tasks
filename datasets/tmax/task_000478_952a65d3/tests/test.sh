#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import runpy
import signal
import sqlite3
import subprocess
import sys
import uuid

import pytest

SCRIPT_PATH = "/home/user/analyze_network.py"
OUTPUT_PATH = "/home/user/shortest_path.json"
DB_PATH = "/home/user/network.db"


def test_script_exists():
    """Keep the original script existence assertions."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_output_json_exists():
    """Keep the original final-output existence assertions."""
    assert os.path.exists(OUTPUT_PATH), f"Output JSON not found at {OUTPUT_PATH}. Did you run the script?"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file"


def test_output_json_content():
    """Keep the original fixed test-case assertions."""
    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    assert "path" in data, "JSON output is missing the 'path' key."
    assert "total_weight" in data, "JSON output is missing the 'total_weight' key."

    expected_path = ["Protein_A", "Chemical_C", "Protein_D", "Disease_Z"]
    expected_weight = 18.0
    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
    assert data["total_weight"] == expected_weight, f"Expected total_weight {expected_weight}, but got {data['total_weight']}."


def read_output():
    assert os.path.isfile(OUTPUT_PATH), "The script did not create shortest_path.json"
    with open(OUTPUT_PATH, "r") as f:
        data = json.load(f)
    assert set(data) == {"path", "total_weight"}
    return data


def database_state():
    with sqlite3.connect(DB_PATH) as conn:
        schema = conn.execute(
            "SELECT type, name, sql FROM sqlite_master "
            "WHERE name IN ('vertices', 'edges') ORDER BY type, name"
        ).fetchall()
        vertices = conn.execute(
            "SELECT v_id, v_name FROM vertices ORDER BY v_id"
        ).fetchall()
        edges = conn.execute(
            "SELECT source_id, target_id, weight FROM edges "
            "ORDER BY source_id, target_id, weight"
        ).fetchall()
    return schema, vertices, edges


def expected_paths(start, end, max_hops):
    """Independently derive all minimum-weight bounded walks from the database."""
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(
            "SELECT s.v_name, t.v_name, e.weight "
            "FROM edges e "
            "JOIN vertices s ON s.v_id = e.source_id "
            "JOIN vertices t ON t.v_id = e.target_id"
        ).fetchall()

    adjacency = {}
    for source, target, weight in rows:
        adjacency.setdefault(source, []).append((target, float(weight)))

    solutions = []
    frontier = [(start, [start], 0.0, 0)]
    while frontier:
        node, path, cost, hops = frontier.pop()
        if node == end:
            solutions.append((cost, path))
        if hops == max_hops:
            continue
        for target, weight in adjacency.get(node, []):
            frontier.append((target, path + [target], cost + weight, hops + 1))

    if not solutions:
        return None, []
    minimum = min(cost for cost, _ in solutions)
    paths = [path for cost, path in solutions if math.isclose(cost, minimum, rel_tol=0, abs_tol=1e-9)]
    return minimum, paths


def assert_result(start, end, max_hops):
    expected_weight, valid_paths = expected_paths(start, end, max_hops)
    data = read_output()
    if expected_weight is None:
        assert data == {"path": [], "total_weight": None}
    else:
        assert data["path"] in valid_paths
        assert isinstance(data["total_weight"], (int, float)) and not isinstance(data["total_weight"], bool)
        assert math.isclose(float(data["total_weight"]), expected_weight, rel_tol=0, abs_tol=1e-9)


def run_script(start, end, max_hops):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, "--start", start, "--end", end,
         "--max-hops", str(max_hops)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert_result(start, end, max_hops)


def run_traced(start, end, max_hops):
    """Run the CLI while recording SQLite use, recursive SQL, parameters, and closure."""
    real_connect = sqlite3.connect
    missing = object()
    statements = []
    connections = []

    class TracingCursor(sqlite3.Cursor):
        def execute(self, sql, parameters=missing):
            statements.append((str(sql), parameters is not missing))
            if parameters is missing:
                return super().execute(sql)
            return super().execute(sql, parameters)

        def executemany(self, sql, seq):
            statements.append((str(sql), True))
            return super().executemany(sql, seq)

    class TracingConnection(sqlite3.Connection):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.was_closed = False
            connections.append(self)

        def cursor(self, *args, **kwargs):
            kwargs.setdefault("factory", TracingCursor)
            return super().cursor(*args, **kwargs)

        def execute(self, sql, parameters=missing):
            statements.append((str(sql), parameters is not missing))
            if parameters is missing:
                return super().execute(sql)
            return super().execute(sql, parameters)

        def executemany(self, sql, seq):
            statements.append((str(sql), True))
            return super().executemany(sql, seq)

        def close(self):
            self.was_closed = True
            return super().close()

    def traced_connect(*args, **kwargs):
        kwargs.setdefault("factory", TracingConnection)
        return real_connect(*args, **kwargs)

    old_argv = sys.argv[:]
    old_connect = sqlite3.connect
    old_handler = signal.getsignal(signal.SIGALRM)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    try:
        sqlite3.connect = traced_connect
        sys.argv = [SCRIPT_PATH, "--start", start, "--end", end,
                    "--max-hops", str(max_hops)]
        signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("script timed out")))
        signal.alarm(10)
        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"Script exited with status {exc.code}"
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)
        sqlite3.connect = old_connect
        sys.argv = old_argv

    assert connections, "The script did not open the SQLite database"
    assert all(conn.was_closed for conn in connections), "The script did not close every database connection"
    recursive = [(sql, parameterized) for sql, parameterized in statements
                 if "WITH RECURSIVE" in sql.upper()]
    assert recursive, "The script did not execute a recursive CTE"
    assert any(parameterized for _, parameterized in recursive), (
        "The recursive graph query was not executed with bound parameters"
    )
    assert_result(start, end, max_hops)


def test_cli_queries_hop_limits_no_path_and_sql_safety():
    token = uuid.uuid4().hex
    start = "verify_start_" + token
    via_a = "verify_a_" + token
    via_b = "verify_b_" + token
    via_c = "verify_c_" + token
    target = "verify_target_" + token
    isolated = "verify_isolated_" + token
    injection = "verify_' OR 1=1 --_" + token

    with sqlite3.connect(DB_PATH) as conn:
        names = [start, via_a, via_b, via_c, target, isolated, injection]
        ids = {}
        for name in names:
            cur = conn.execute("INSERT INTO vertices(v_name) VALUES (?)", (name,))
            ids[name] = cur.lastrowid
        conn.executemany(
            "INSERT INTO edges(source_id, target_id, weight) VALUES (?, ?, ?)",
            [
                (ids[start], ids[target], 20.0),
                (ids[start], ids[via_a], 7.0),
                (ids[via_a], ids[target], 8.0),
                (ids[start], ids[via_b], 1.0),
                (ids[via_b], ids[via_c], 1.0),
                (ids[via_c], ids[target], 1.0),
                (ids[via_b], ids[start], 0.5),
                (ids[injection], ids[target], 4.25),
            ],
        )

    pristine = database_state()

    # Execute the required recursive, parameterized SQLite behavior under tracing.
    run_traced(start, target, 3)
    assert database_state() == pristine, "The analysis script modified the database"

    # Exercise distinct hop limits, including paths whose optimum changes.
    run_script(start, target, 1)
    assert database_state() == pristine
    run_script(start, target, 2)
    assert database_state() == pristine

    # Exercise no-path handling.
    run_script(target, isolated, 4)
    assert database_state() == pristine

    # A hostile node name must be treated as data, not SQL syntax.
    run_script(injection, target, 1)
    assert database_state() == pristine, "Unsafe SQL handling modified the database"

    # Also execute the documented command rather than trusting the pre-generated file.
    run_script("Protein_A", "Disease_Z", 3)
    assert database_state() == pristine
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
