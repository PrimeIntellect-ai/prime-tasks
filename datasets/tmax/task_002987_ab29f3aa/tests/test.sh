#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import heapq
import json
import os
import secrets
import sqlite3
import subprocess
import sys
import tempfile
import uuid

import pytest

QUERY_PATH = "/home/user/fixed_query.sql"
DB_PATH = "/home/user/network.db"
GRAPH_PATH = "/home/user/graph.json"
SCRIPT_PATH = "/home/user/solve_path.py"
RESULT_PATH = "/home/user/result.json"

EXPECTED_EDGES = {
    ("Start", "N1"): 1000.0,
    ("Start", "N2"): 800.0,
    ("N1", "End"): 100.0,
    ("N2", "End"): 200.0,
    ("N3", "End"): 10000.0,
}


def read_query():
    assert os.path.isfile(QUERY_PATH), f"File {QUERY_PATH} is missing or is not a regular file."
    with open(QUERY_PATH, "r") as f:
        return f.read()


def execute_query(query, db_path):
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute(query)
        rows = cursor.fetchall()
        columns = [desc[0].lower() for desc in cursor.description]
        return columns, rows
    except sqlite3.Error as e:
        pytest.fail(f"Executing fixed_query.sql failed: {e}")
    finally:
        conn.close()


def normalized_query_edges(columns, rows):
    assert "source" in columns, "Query must return 'source' column"
    assert "target" in columns, "Query must return 'target' column"
    assert "bandwidth" in columns, "Query must return 'bandwidth' column"
    source_idx = columns.index("source")
    target_idx = columns.index("target")
    bw_idx = columns.index("bandwidth")
    return [(row[source_idx], row[target_idx], float(row[bw_idx])) for row in rows]


def test_fixed_query_sql_exists_and_correct():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    query = read_query()
    columns, rows = execute_query(query, DB_PATH)
    edges = normalized_query_edges(columns, rows)

    actual_edges = {(source, target): bandwidth for source, target, bandwidth in edges}
    assert actual_edges == EXPECTED_EDGES, f"Query results did not match expected top-2 links. Got: {actual_edges}"
    assert len(edges) == len(EXPECTED_EDGES), "Query returned duplicate or additional rows."


def test_fixed_query_on_unseen_database():
    query = read_query()
    suffix = uuid.uuid4().hex
    names = {
        11: "source_a_" + suffix,
        12: "source_b_" + suffix,
        21: "alpha_" + suffix,
        22: "beta_" + suffix,
        23: "gamma_" + suffix,
        24: "delta_" + suffix,
        25: "epsilon_" + suffix,
    }
    servers = list(names.items())
    links = [
        (11, 21, 730.0),
        (11, 22, 730.0),
        (11, 23, 940.0),
        (11, 24, 120.0),
        (12, 21, 410.0),
        (12, 24, 880.0),
        (12, 25, 640.0),
    ]

    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        conn = sqlite3.connect(path)
        cur = conn.cursor()
        cur.execute("CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT)")
        cur.execute("CREATE TABLE links (source_id INTEGER, target_id INTEGER, bandwidth REAL)")
        cur.executemany("INSERT INTO servers VALUES (?, ?)", servers)
        cur.executemany("INSERT INTO links VALUES (?, ?, ?)", links)
        conn.commit()
        conn.close()

        expected = []
        for source_id in {row[0] for row in links}:
            candidates = [row for row in links if row[0] == source_id]
            candidates.sort(key=lambda row: (-row[2], names[row[1]]))
            for _, target_id, bandwidth in candidates[:2]:
                expected.append((names[source_id], names[target_id], float(bandwidth)))

        columns, rows = execute_query(query, path)
        actual = normalized_query_edges(columns, rows)
        assert collections.Counter(actual) == collections.Counter(expected), (
            f"Query did not perform the required joins/top-2 tie-breaking on an unseen database. Got: {actual}"
        )
    finally:
        if os.path.exists(path):
            os.unlink(path)


def test_graph_json_exists_and_correct():
    assert os.path.isfile(GRAPH_PATH), f"File {GRAPH_PATH} is missing or is not a regular file."
    with open(GRAPH_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{GRAPH_PATH} is not valid JSON.")

    assert isinstance(data, list), f"{GRAPH_PATH} must contain a JSON array."
    actual_edges = {}
    normalized_graph = []
    for item in data:
        assert isinstance(item, dict), "Every graph entry must be a JSON object."
        assert "source" in item, "JSON object missing 'source'"
        assert "target" in item, "JSON object missing 'target'"
        assert "bandwidth" in item, "JSON object missing 'bandwidth'"
        assert set(item) == {"source", "target", "bandwidth"}, "Graph objects must have exactly the required fields."
        edge = (item["source"], item["target"], float(item["bandwidth"]))
        normalized_graph.append(edge)
        actual_edges[(item["source"], item["target"])] = float(item["bandwidth"])

    assert actual_edges == EXPECTED_EDGES, f"Data in {GRAPH_PATH} does not match expected output."
    assert len(data) == len(EXPECTED_EDGES), "graph.json contains duplicate or additional rows."

    columns, rows = execute_query(read_query(), DB_PATH)
    query_edges = normalized_query_edges(columns, rows)
    assert collections.Counter(normalized_graph) == collections.Counter(query_edges), (
        "graph.json must contain the rows produced by fixed_query.sql."
    )


def reference_shortest_path(edges):
    adjacency = collections.defaultdict(list)
    for edge in edges:
        bandwidth = float(edge["bandwidth"])
        assert bandwidth > 0
        adjacency[edge["source"]].append((edge["target"], 10000.0 / bandwidth))

    queue = [(0.0, "Start")]
    distances = {"Start": 0.0}
    previous = {}
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distances.get(node):
            continue
        if node == "End":
            break
        for target, edge_cost in adjacency[node]:
            candidate = cost + edge_cost
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert "End" in distances
    path = ["End"]
    while path[-1] != "Start":
        path.append(previous[path[-1]])
    path.reverse()
    return path, distances["End"]


def run_solver_and_read_result():
    if os.path.exists(RESULT_PATH):
        os.unlink(RESULT_PATH)
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, f"solve_path.py failed: {completed.stderr}"
    assert os.path.isfile(RESULT_PATH), "solve_path.py did not write /home/user/result.json"
    with open(RESULT_PATH, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("solve_path.py wrote invalid JSON to result.json")
    assert isinstance(result, dict)
    assert "path" in result, "Result JSON missing 'path'"
    assert "cost" in result, "Result JSON missing 'cost'"
    assert set(result) == {"path", "cost"}, "result.json must have exactly path and cost fields."
    return result


def test_solve_path_py_exists_and_executes_dynamic_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing or is not a regular file."
    with open(GRAPH_PATH, "rb") as f:
        original_graph = f.read()

    token = uuid.uuid4().hex
    a = "A_" + token
    b = "B_" + token
    c = "C_" + token
    jitter = secrets.randbelow(40)
    cases = [
        [
            {"source": "Start", "target": a, "bandwidth": 800.0 + jitter},
            {"source": a, "target": "End", "bandwidth": 760.0},
            {"source": "Start", "target": b, "bandwidth": 1700.0},
            {"source": b, "target": "End", "bandwidth": 205.0},
            {"source": "Start", "target": "End", "bandwidth": 300.0},
            {"source": "End", "target": "Start", "bandwidth": 99999.0},
        ],
        [
            {"source": "Start", "target": a, "bandwidth": 260.0},
            {"source": a, "target": "End", "bandwidth": 240.0},
            {"source": "Start", "target": b, "bandwidth": 1250.0 + jitter},
            {"source": b, "target": c, "bandwidth": 1150.0},
            {"source": c, "target": "End", "bandwidth": 1050.0},
            {"source": "Start", "target": "End", "bandwidth": 220.0},
            {"source": "End", "target": b, "bandwidth": 50000.0},
        ],
    ]

    try:
        for edges in cases:
            with open(GRAPH_PATH, "w") as f:
                json.dump(edges, f)
            expected_path, expected_cost = reference_shortest_path(edges)
            result = run_solver_and_read_result()
            assert result["path"] == expected_path, f"Incorrect dynamic path: {result['path']}"
            assert isinstance(result["cost"], (int, float)), "Result cost must be numeric."
            assert abs(float(result["cost"]) - expected_cost) < 1e-6, (
                f"Incorrect dynamic cost. Expected {expected_cost}, got {result['cost']}"
            )
    finally:
        with open(GRAPH_PATH, "wb") as f:
            f.write(original_graph)

    result = run_solver_and_read_result()
    assert result["path"] == ["Start", "N2", "End"], (
        f"Incorrect path. Expected ['Start', 'N2', 'End'], got {result['path']}"
    )
    assert abs(float(result["cost"]) - 62.5) < 1e-6, f"Incorrect cost. Expected 62.5, got {result['cost']}"


def test_result_json_exists_and_correct():
    assert os.path.exists(RESULT_PATH), f"File {RESULT_PATH} is missing."
    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_PATH} is not valid JSON.")

    assert "path" in data, "Result JSON missing 'path'"
    assert "cost" in data, "Result JSON missing 'cost'"
    assert data["path"] == ["Start", "N2", "End"], f"Incorrect path. Expected ['Start', 'N2', 'End'], got {data['path']}"
    assert abs(data["cost"] - 62.5) < 1e-6, f"Incorrect cost. Expected 62.5, got {data['cost']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
