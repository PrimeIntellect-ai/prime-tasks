#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/route_verifier_hook

cat << 'HOOK_EOF' > /tmp/route_verifier_hook/sitecustomize.py
import json
import os
import sqlite3

_original_connect = sqlite3.connect
_log_path = os.environ.get("ROUTE_SQL_TRACE")

def _log(operation, sql=None, parameters=None, supplied=False):
    if not _log_path:
        return
    record = {
        "operation": operation,
        "sql": sql,
        "parameters": parameters,
        "parameters_supplied": supplied,
    }
    try:
        with open(_log_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, default=str) + "\n")
    except Exception:
        pass

class CursorProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name == "_inner":
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)

    def __iter__(self):
        return iter(self._inner)

    def execute(self, sql, parameters=...):
        supplied = parameters is not ...
        _log("execute", sql, None if not supplied else parameters, supplied)
        if supplied:
            self._inner.execute(sql, parameters)
        else:
            self._inner.execute(sql)
        return self

    def executemany(self, sql, seq_of_parameters):
        materialized = list(seq_of_parameters)
        _log("executemany", sql, materialized, True)
        self._inner.executemany(sql, materialized)
        return self

    def executescript(self, sql):
        _log("executescript", sql, None, False)
        self._inner.executescript(sql)
        return self

class ConnectionProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name == "_inner":
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._inner.cursor(*args, **kwargs))

    def execute(self, sql, parameters=...):
        supplied = parameters is not ...
        _log("execute", sql, None if not supplied else parameters, supplied)
        if supplied:
            cursor = self._inner.execute(sql, parameters)
        else:
            cursor = self._inner.execute(sql)
        return CursorProxy(cursor)

    def executemany(self, sql, seq_of_parameters):
        materialized = list(seq_of_parameters)
        _log("executemany", sql, materialized, True)
        return CursorProxy(self._inner.executemany(sql, materialized))

    def executescript(self, sql):
        _log("executescript", sql, None, False)
        return CursorProxy(self._inner.executescript(sql))

def connect(*args, **kwargs):
    _log("connect", str(args[0]) if args else str(kwargs.get("database")))
    return ConnectionProxy(_original_connect(*args, **kwargs))

sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/route_optimizer.py"
OUTPUT_PATH = "/home/user/optimal_route.json"
NETWORK_PATH = "/home/user/network.csv"
TRACE_PATH = "/tmp/route_optimizer_sql_trace.jsonl"
HOOK_PATH = "/tmp/route_verifier_hook"

def run_script(start_node, end_node, max_cost):
    """Helper to run the student's script."""
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = HOOK_PATH if not old_pythonpath else HOOK_PATH + os.pathsep + old_pythonpath
    env["ROUTE_SQL_TRACE"] = TRACE_PATH
    result = subprocess.run(
        ["python3", SCRIPT_PATH, start_node, end_node, str(max_cost)],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )
    return result

def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH} after running script."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

def test_script_exists():
    """Verify that the student created the script."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

def test_route_optimizer_scenario_1():
    """Test with parameters A D 15."""
    assert os.path.isfile(SCRIPT_PATH), "Script missing."

    run_script("A", "D", 15)

    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH} after running script."

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    assert "path" in data, "JSON output missing 'path' key."
    assert "total_time" in data, "JSON output missing 'total_time' key."

    assert data["path"] == ["A", "B", "E", "D"], f"Expected path ['A', 'B', 'E', 'D'], got {data['path']}"
    assert data["total_time"] == 20, f"Expected total_time 20, got {data['total_time']}"

def test_route_optimizer_scenario_2():
    """Test with parameters A D 5."""
    assert os.path.isfile(SCRIPT_PATH), "Script missing."

    run_script("A", "D", 5)

    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH} after running script."

    with open(OUTPUT_PATH, "r") as f:
        data = json.load(f)

    assert data["path"] == ["A", "C", "D"], f"Expected path ['A', 'C', 'D'], got {data['path']}"
    assert data["total_time"] == 25, f"Expected total_time 25, got {data['total_time']}"

def test_route_optimizer_no_path():
    """Test with parameters A B 1 (no valid path)."""
    assert os.path.isfile(SCRIPT_PATH), "Script missing."

    run_script("A", "B", 1)

    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH} after running script."

    with open(OUTPUT_PATH, "r") as f:
        data = json.load(f)

    assert data["path"] == [], f"Expected empty path [], got {data['path']}"
    assert data["total_time"] is None, f"Expected total_time null, got {data['total_time']}"

def write_network(rows):
    with open(NETWORK_PATH, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["source", "target", "time", "cost"])
        writer.writerows(rows)

def shortest_time(rows, start, end, max_cost):
    graph = {}
    for source, target, travel_time, cost in rows:
        if cost <= max_cost:
            graph.setdefault(source, []).append((target, travel_time))
    distances = {start: 0}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == end:
            return distance
        for target, travel_time in graph.get(node, []):
            candidate = distance + travel_time
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))
    return None

def parameter_contains(parameters, expected):
    if isinstance(parameters, dict):
        return any(parameter_contains(value, expected) for value in parameters.values())
    if isinstance(parameters, (list, tuple)):
        return any(parameter_contains(value, expected) for value in parameters)
    return str(parameters) == str(expected)

def assert_parameterized_cost_query(max_cost):
    assert os.path.isfile(TRACE_PATH), "No SQLite activity was observed."
    records = []
    with open(TRACE_PATH, "r", encoding="utf-8") as handle:
        for line in handle:
            records.append(json.loads(line))
    assert any(record.get("operation") == "connect" for record in records), "The script did not open a SQLite database."

    matching = []
    for record in records:
        sql = record.get("sql") or ""
        normalized = " ".join(sql.lower().split())
        if (
            "select" in normalized
            and "cost" in normalized
            and "<=" in normalized
            and record.get("parameters_supplied")
            and re.search(r"\?|:[A-Za-z_]\w*|@[A-Za-z_]\w*|\$[A-Za-z_]\w*", sql)
            and parameter_contains(record.get("parameters"), max_cost)
        ):
            matching.append(record)
    assert matching, "No parameterized SQLite SELECT filtering cost <= max_edge_cost was observed."

def validate_result(rows, start, end, max_cost, data):
    assert isinstance(data, dict), "Top-level JSON value must be an object."
    assert set(data.keys()) == {"path", "total_time"}, "JSON must contain exactly 'path' and 'total_time'."
    expected_time = shortest_time(rows, start, end, max_cost)

    if expected_time is None:
        assert data["path"] == []
        assert data["total_time"] is None
        return

    path = data["path"]
    assert isinstance(path, list) and path, "A reachable route must have a non-empty path list."
    assert path[0] == start and path[-1] == end, "Path endpoints are incorrect."
    allowed_edges = {
        (source, target): travel_time
        for source, target, travel_time, cost in rows
        if cost <= max_cost
    }
    actual_time = 0
    for source, target in zip(path, path[1:]):
        assert (source, target) in allowed_edges, f"Path uses unavailable edge {source}->{target}."
        actual_time += allowed_edges[(source, target)]
    assert actual_time == expected_time, "Returned path is not a shortest path."
    assert data["total_time"] == expected_time, "total_time is not the shortest-path time."

def test_randomized_networks_and_sqlite_query():
    """Exercise unseen node names, networks, limits, and routes derived at verification time."""
    with open(NETWORK_PATH, "rb") as handle:
        original_network = handle.read()

    try:
        for iteration in range(6):
            nodes = [f"N_{secrets.token_hex(5)}" for _ in range(8)]
            start, middle, end = nodes[0], nodes[1], nodes[2]
            max_cost = 5 + secrets.randbelow(16)
            edges = {}

            for source in nodes:
                for target in nodes:
                    if source != target and secrets.randbelow(100) < 28:
                        edges[(source, target)] = (
                            1 + secrets.randbelow(30),
                            1 + secrets.randbelow(25),
                        )

            # Guarantee at least one permitted route while retaining random distractors.
            edges[(start, middle)] = (2 + secrets.randbelow(8), 1 + secrets.randbelow(max_cost))
            edges[(middle, end)] = (2 + secrets.randbelow(8), 1 + secrets.randbelow(max_cost))
            edges[(start, end)] = (25 + secrets.randbelow(20), 1 + secrets.randbelow(max_cost))
            rows = [
                (source, target, travel_time, cost)
                for (source, target), (travel_time, cost) in edges.items()
            ]
            write_network(rows)

            result = run_script(start, end, max_cost)
            assert result.returncode == 0, f"Script failed: {result.stderr}"
            data = load_output()
            validate_result(rows, start, end, max_cost, data)
            assert_parameterized_cost_query(max_cost)

        # A fresh, unpredictable no-path case with a threshold below every edge cost.
        nodes = [f"Z_{secrets.token_hex(5)}" for _ in range(5)]
        rows = [
            (nodes[0], nodes[1], 3, 1),
            (nodes[1], nodes[2], 4, 2),
            (nodes[2], nodes[4], 5, 3),
            (nodes[3], nodes[4], 1, 1),
        ]
        write_network(rows)
        result = run_script(nodes[0], nodes[4], 0)
        assert result.returncode == 0, f"Script failed: {result.stderr}"
        data = load_output()
        validate_result(rows, nodes[0], nodes[4], 0, data)
        assert_parameterized_cost_query(0)
    finally:
        with open(NETWORK_PATH, "wb") as handle:
            handle.write(original_network)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
