#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/optimize_access.py"
GRAPH_PATH = "/home/user/graph_data.json"
OUTPUT_PATH = "/home/user/access_path.json"


def run_submission():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found after execution: {OUTPUT_PATH}"


def load_output():
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON")


def shortest_distance(graph, start, target):
    adjacency = {node: [] for node in graph["nodes"]}
    for edge in graph["edges"]:
        adjacency.setdefault(edge["source"], []).append(edge["target"])

    queue = deque([(start, 0)])
    visited = {start}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for neighbor in adjacency.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def assert_valid_shortest_path(data, graph):
    assert "path" in data, f"Key 'path' missing in {OUTPUT_PATH}"
    assert "distance" in data, f"Key 'distance' missing in {OUTPUT_PATH}"
    assert isinstance(data["path"], list), "'path' must be a list"
    assert isinstance(data["distance"], int), "'distance' must be an integer"

    path = data["path"]
    assert path, "'path' must not be empty"
    assert path[0] == "U_105", "Path must start at U_105"
    assert path[-1] == "R_992", "Path must end at R_992"
    assert data["distance"] == len(path) - 1, "Distance must equal the number of path edges"

    nodes = set(graph["nodes"])
    directed_edges = {(edge["source"], edge["target"]) for edge in graph["edges"]}
    assert all(node in nodes for node in path), "Path contains a node absent from the graph"
    assert all((source, target) in directed_edges for source, target in zip(path, path[1:])), (
        "Path contains an edge absent from the graph"
    )

    expected_distance = shortest_distance(graph, "U_105", "R_992")
    assert expected_distance is not None, "Verifier graph unexpectedly has no path"
    assert data["distance"] == expected_distance, (
        f"Expected shortest distance {expected_distance}, got {data['distance']}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_original_graph():
    assert os.path.exists(SCRIPT_PATH), f"Required script not found: {SCRIPT_PATH}"
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"Required script is not a regular file: {SCRIPT_PATH}"

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_submission()


def test_access_path_exists_and_valid():
    output_path = "/home/user/access_path.json"

    assert os.path.isfile(output_path), f"Output file not found: {output_path}"

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON")

    assert "path" in data, f"Key 'path' missing in {output_path}"
    assert "distance" in data, f"Key 'distance' missing in {output_path}"

    assert isinstance(data["path"], list), "'path' must be a list"
    assert isinstance(data["distance"], int), "'distance' must be an integer"


def test_access_path_correctness():
    output_path = "/home/user/access_path.json"

    if not os.path.isfile(output_path):
        pytest.skip("Output file does not exist, skipping correctness check.")

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Output file is not valid JSON, skipping correctness check.")

    expected_path = ["U_105", "Role_A", "Role_B", "R_992"]
    expected_distance = 3

    assert data["distance"] == expected_distance, f"Expected distance {expected_distance}, got {data.get('distance')}"
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data.get('path')}"


def test_script_traverses_graph_data():
    with open(GRAPH_PATH, "rb") as f:
        original_graph = f.read()
    with open(OUTPUT_PATH, "rb") as f:
        original_output = f.read()

    token = uuid.uuid4().hex
    a, b, c, d, e, orphan = [f"N_{token}_{name}" for name in "abcdef"]

    cases = [
        {
            "nodes": ["U_105", "R_992", a, b, c, orphan],
            "edges": [
                {"source": "U_105", "target": a, "type": "has_role"},
                {"source": a, "target": "R_992", "type": "can_read"},
                {"source": "U_105", "target": b, "type": "has_role"},
                {"source": b, "target": c, "type": "inherits"},
                {"source": c, "target": "R_992", "type": "can_read"},
                {"source": orphan, "target": "R_992", "type": "can_read"},
            ],
        },
        {
            "nodes": ["U_105", "R_992", a, b, c, d, e, orphan],
            "edges": [
                {"source": "U_105", "target": a, "type": "has_role"},
                {"source": a, "target": b, "type": "inherits"},
                {"source": b, "target": c, "type": "inherits"},
                {"source": c, "target": "R_992", "type": "can_read"},
                {"source": b, "target": a, "type": "inherits"},
                {"source": "U_105", "target": d, "type": "has_role"},
                {"source": d, "target": e, "type": "inherits"},
                {"source": e, "target": orphan, "type": "inherits"},
            ],
        },
    ]

    try:
        for graph in cases:
            with open(GRAPH_PATH, "w") as f:
                json.dump(graph, f)
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            run_submission()
            assert_valid_shortest_path(load_output(), graph)
    finally:
        with open(GRAPH_PATH, "wb") as f:
            f.write(original_graph)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
