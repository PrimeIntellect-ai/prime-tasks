#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
from collections import deque

import pytest

SOURCE_PATH = "/home/user/graph_optimizer.cpp"
EXECUTABLE_PATH = "/home/user/graph_optimizer"
REPORT_PATH = "/home/user/optimization_report.json"

EXPECTED_TOP_DEPENDENCIES = [
    "raw_transactions",
    "clean_transactions",
    "regional_sales_view",
]
EXPECTED_SHORTEST_PATH = [
    "monthly_sales_report",
    "regional_sales_view",
    "clean_transactions",
    "raw_transactions",
]


def test_cpp_source_and_executable_exist():
    assert os.path.exists(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    assert os.path.isfile(SOURCE_PATH), f"Path {SOURCE_PATH} is not a file."

    assert os.path.exists(EXECUTABLE_PATH), f"Executable file {EXECUTABLE_PATH} is missing. Did you compile the code?"
    assert os.path.isfile(EXECUTABLE_PATH), f"Path {EXECUTABLE_PATH} is not a file."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File {EXECUTABLE_PATH} is not executable."


def test_optimization_report_json():
    assert os.path.exists(REPORT_PATH), f"The output JSON file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file."

    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON. Error: {e}")

    assert "top_dependencies" in data, "Key 'top_dependencies' is missing in the JSON output."
    assert "shortest_path" in data, "Key 'shortest_path' is missing in the JSON output."

    assert data["top_dependencies"] == EXPECTED_TOP_DEPENDENCIES, \
        f"Expected top_dependencies to be {EXPECTED_TOP_DEPENDENCIES}, but got {data['top_dependencies']}"
    assert data["shortest_path"] == EXPECTED_SHORTEST_PATH, \
        f"Expected shortest_path to be {EXPECTED_SHORTEST_PATH}, but got {data['shortest_path']}"


def run_tool(binary, graph_path, source, target):
    result = subprocess.run(
        [binary, graph_path, source, target],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, f"{binary} failed: {result.stderr}"
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        pytest.fail(f"{binary} did not emit valid JSON: {e}; output={result.stdout!r}")


def validate_result(data, nodes, edges, source, target):
    assert "top_dependencies" in data
    assert "shortest_path" in data

    indegree = {node: 0 for node in nodes}
    adjacency = {node: [] for node in nodes}
    for dependant, dependency in edges:
        indegree[dependency] += 1
        adjacency[dependant].append(dependency)

    expected_top = sorted(nodes, key=lambda node: (-indegree[node], node))[:3]
    assert data["top_dependencies"] == expected_top

    distances = {source: 0}
    queue = deque([source])
    while queue:
        current = queue.popleft()
        for neighbor in adjacency[current]:
            if neighbor not in distances:
                distances[neighbor] = distances[current] + 1
                queue.append(neighbor)

    path = data["shortest_path"]
    assert isinstance(path, list)
    assert path[0] == source
    assert path[-1] == target
    assert len(path) == distances[target] + 1
    edge_set = set(edges)
    assert all((path[i], path[i + 1]) in edge_set for i in range(len(path) - 1))


@pytest.fixture(scope="session")
def rebuilt_binary():
    path = os.path.join(tempfile.gettempdir(), "graph_optimizer_rebuilt_" + secrets.token_hex(8))
    result = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_PATH, "-o", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"The submitted C++ source does not compile: {result.stderr}"
    yield path
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def test_executable_on_required_input():
    actual = run_tool(
        EXECUTABLE_PATH,
        "/home/user/schema_deps.txt",
        "monthly_sales_report",
        "raw_transactions",
    )
    assert actual["top_dependencies"] == EXPECTED_TOP_DEPENDENCIES
    assert actual["shortest_path"] == EXPECTED_SHORTEST_PATH

    with open(REPORT_PATH, "r") as f:
        report = json.load(f)
    assert actual == report


def test_dynamic_graph_analytics_and_traversal(rebuilt_binary):
    binaries = [EXECUTABLE_PATH, rebuilt_binary]

    with tempfile.TemporaryDirectory(prefix="graph_optimizer_test_") as temp_dir:
        for case_number in range(4):
            nodes = ["obj_" + secrets.token_hex(6) for _ in range(9)]
            source = nodes[0]
            target = nodes[8]

            edges = {
                (nodes[0], nodes[1]),
                (nodes[1], nodes[2]),
                (nodes[2], nodes[8]),
                (nodes[3], nodes[8]),
                (nodes[4], nodes[7]),
                (nodes[5], nodes[7]),
                (nodes[6], nodes[4]),
                (nodes[7], nodes[8]),
            }

            random_bytes = secrets.token_bytes(len(nodes) * len(nodes))
            byte_index = 0
            for left in nodes:
                for right in nodes:
                    value = random_bytes[byte_index]
                    byte_index += 1
                    if left != right and value < 38:
                        edges.add((left, right))

            edge_list = list(edges)
            graph_path = os.path.join(temp_dir, f"case_{case_number}_{secrets.token_hex(4)}.txt")
            with open(graph_path, "w") as graph_file:
                for dependant, dependency in edge_list:
                    graph_file.write(f"{dependant} {dependency}\n")

            for binary in binaries:
                data = run_tool(binary, graph_path, source, target)
                validate_result(data, nodes, edge_list, source, target)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
