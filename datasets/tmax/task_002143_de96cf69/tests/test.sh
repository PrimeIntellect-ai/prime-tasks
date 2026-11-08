#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import secrets
import stat
import subprocess

import pytest

SCRIPT = "/home/user/process_graph.py"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"
RESULT = "/home/user/result.json"

ORIGINAL_NODES = [
    ["node_id", "node_type", "base_value"],
    ["A", "hub", "10"],
    ["B", "warehouse", "20"],
    ["C", "hub", "30"],
    ["D", "sorting", "40"],
    ["E", "warehouse", "50"],
    ["F", "hub", "15"],
]

ORIGINAL_EDGES = [
    ["src", "dst", "cost"],
    ["A", "B", "5"],
    ["A", "C", "15"],
    ["A", "F", "2"],
    ["F", "B", "10"],
    ["B", "C", "8"],
    ["C", "D", "10"],
    ["B", "E", "25"],
    ["D", "E", "5"],
    ["F", "E", "40"],
]


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        csv.writer(f).writerows(rows)


def write_inputs(nodes, edges):
    write_csv(NODES, nodes)
    write_csv(EDGES, edges)


def run_submission():
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"{SCRIPT} must be a regular file."
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT} exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def load_result():
    assert os.path.exists(RESULT), f"The output file {RESULT} was not created."
    with open(RESULT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULT} does not contain valid JSON.")


def assert_schema(data):
    expected_keys = {"shortest_path_cost", "total_node_value", "path"}
    assert set(data.keys()) == expected_keys, (
        f"The JSON schema is incorrect. Expected keys: {expected_keys}, "
        f"Found: {set(data.keys())}"
    )
    assert isinstance(data["shortest_path_cost"], int), "shortest_path_cost must be an integer."
    assert isinstance(data["total_node_value"], int), "total_node_value must be an integer."
    assert isinstance(data["path"], list), "path must be a list of strings."
    assert all(isinstance(x, str) for x in data["path"]), "path must be a list of strings."


def derive_expected():
    values = {}
    with open(NODES, newline="") as f:
        for row in csv.DictReader(f):
            values[row["node_id"]] = int(row["base_value"])

    graph = {node: [] for node in values}
    with open(EDGES, newline="") as f:
        for row in csv.DictReader(f):
            graph.setdefault(row["src"], []).append((row["dst"], int(row["cost"])))

    queue = [(0, "A", ["A"])]
    best = {}
    while queue:
        cost, node, path = heapq.heappop(queue)
        if node in best and best[node] <= cost:
            continue
        best[node] = cost
        if node == "E":
            return {
                "shortest_path_cost": cost,
                "total_node_value": sum(values[item] for item in path),
                "path": path,
            }
        for destination, edge_cost in graph.get(node, []):
            heapq.heappush(queue, (cost + edge_cost, destination, path + [destination]))
    raise AssertionError("Verifier-generated graph unexpectedly has no path from A to E")


@pytest.fixture(scope="session", autouse=True)
def restore_original_inputs():
    yield
    write_inputs(ORIGINAL_NODES, ORIGINAL_EDGES)


def test_result_json_exists_and_correct():
    write_inputs(ORIGINAL_NODES, ORIGINAL_EDGES)
    run_submission()
    data = load_result()

    # Preserve the original schema, type, and exact fixture assertions.
    assert_schema(data)
    assert data["shortest_path_cost"] == 28, (
        f"Incorrect shortest_path_cost. Expected 28, got {data['shortest_path_cost']}."
    )
    assert data["total_node_value"] == 150, (
        f"Incorrect total_node_value. Expected 150, got {data['total_node_value']}."
    )
    expected_path = ["A", "B", "C", "D", "E"]
    assert data["path"] == expected_path, (
        f"Incorrect path. Expected {expected_path}, got {data['path']}."
    )


def test_script_processes_changed_csv_inputs():
    rng = secrets.SystemRandom()
    node_values = {node: rng.randint(3, 90) for node in ["A", "Q", "R", "S", "T", "E"]}
    nodes = [["node_id", "node_type", "base_value"]] + [
        [node, "hub", str(node_values[node])] for node in ["A", "Q", "R", "S", "T", "E"]
    ]

    # The low-cost route is unique, while all costs and node values vary per run.
    edges = [
        ["src", "dst", "cost"],
        ["A", "Q", str(rng.randint(1, 5))],
        ["Q", "R", str(rng.randint(1, 5))],
        ["R", "E", str(rng.randint(1, 5))],
        ["A", "S", str(rng.randint(20, 30))],
        ["S", "E", str(rng.randint(20, 30))],
        ["A", "T", str(rng.randint(25, 35))],
        ["T", "E", str(rng.randint(20, 30))],
        ["Q", "E", str(rng.randint(30, 45))],
        ["S", "T", str(rng.randint(8, 15))],
        ["R", "Q", str(rng.randint(1, 5))],
    ]
    write_inputs(nodes, edges)
    expected = derive_expected()

    run_submission()
    data = load_result()
    assert_schema(data)
    assert data == expected, f"Incorrect result for changed CSV inputs. Expected {expected}, got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
