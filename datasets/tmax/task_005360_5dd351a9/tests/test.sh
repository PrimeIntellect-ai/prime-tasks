#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import math
import os
import secrets
import stat
import subprocess
import time

import pytest

FAST_SCRIPT = "/home/user/fast_traversal.py"
SLOW_SCRIPT = "/home/user/slow_traversal.py"
GRAPH_FILE = "/home/user/infrastructure_graph.json"
RESULT_FILE = "/home/user/path_result.json"
START = "SRV-EDGE-42"
DESTINATION = "DB-CORE-99"

TRUSTED_SLOW = r'''import sys
import json

def find_shortest_path(graph, start, end, path=None, latency=0):
    if path is None:
        path = []
    path = path + [start]
    if start == end:
        return path, latency
    if start not in graph:
        return None, float('inf')

    shortest = None
    min_latency = float('inf')

    for node, weight in graph[start].items():
        if node not in path:
            new_path, new_latency = find_shortest_path(graph, node, end, path, latency + weight)
            if new_path:
                if new_latency < min_latency:
                    shortest = new_path
                    min_latency = new_latency

    return shortest, min_latency

if __name__ == "__main__":
    start_node, graph_file, result_file = sys.argv[1:4]
    with open(graph_file, "r") as f:
        graph = json.load(f)
    path, latency = find_shortest_path(graph, start_node, "DB-CORE-99")
    with open(result_file, "w") as f:
        json.dump({"start_node": start_node, "path": path, "total_latency": latency}, f)
'''


def run_command(command, timeout):
    started = time.perf_counter()
    result = subprocess.run(command, capture_output=True, timeout=timeout)
    elapsed = time.perf_counter() - started
    assert result.returncode == 0, (
        f"Command {command!r} failed with stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return elapsed


def shortest_path(graph, start, destination):
    distances = {start: 0}
    previous = {}
    queue = [(0, start)]

    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == destination:
            break
        for neighbor, weight in graph.get(node, {}).items():
            assert isinstance(weight, (int, float)) and not isinstance(weight, bool)
            assert weight >= 0
            candidate = distance + weight
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                previous[neighbor] = node
                heapq.heappush(queue, (candidate, neighbor))

    assert destination in distances, "Test graph unexpectedly has no route to DB-CORE-99"
    path = [destination]
    while path[-1] != start:
        path.append(previous[path[-1]])
    path.reverse()
    return path, distances[destination]


def read_and_validate_result(graph, start):
    assert os.path.isfile(RESULT_FILE), f"Missing {RESULT_FILE}"
    try:
        with open(RESULT_FILE, "r") as f:
            result = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {RESULT_FILE} is not valid JSON: {exc}")

    assert isinstance(result, dict), "Result must be a JSON object"
    assert set(result) == {"start_node", "path", "total_latency"}, (
        "Result must contain exactly start_node, path, and total_latency"
    )
    assert result["start_node"] == start, (
        f"Expected start_node {start!r}, got {result['start_node']!r}"
    )
    assert isinstance(result["path"], list), "path must be a list"
    assert result["path"], "path must not be empty"
    assert result["path"][0] == start, "path must begin at the requested start node"
    assert result["path"][-1] == DESTINATION, "path must end at DB-CORE-99"
    assert isinstance(result["total_latency"], (int, float)) and not isinstance(
        result["total_latency"], bool
    ), "total_latency must be numeric"

    summed_latency = 0
    for source, target in zip(result["path"], result["path"][1:]):
        assert source in graph and target in graph[source], (
            f"Invalid path edge: {source!r} -> {target!r}"
        )
        summed_latency += graph[source][target]

    assert math.isclose(result["total_latency"], summed_latency, rel_tol=1e-12, abs_tol=1e-12), (
        f"total_latency {result['total_latency']!r} does not equal edge sum {summed_latency!r}"
    )

    expected_path, expected_latency = shortest_path(graph, start, DESTINATION)
    assert result["path"] == expected_path, (
        f"Expected shortest path {expected_path!r}, got {result['path']!r}"
    )
    assert math.isclose(result["total_latency"], expected_latency, rel_tol=1e-12, abs_tol=1e-12), (
        f"Expected optimal latency {expected_latency!r}, got {result['total_latency']!r}"
    )
    return result


def build_performance_graph():
    # Opaque labels and runtime-generated weights ensure the result must be
    # computed from the graph rather than hard-coded in the submission.
    token = secrets.token_hex(5)
    intermediate = [f"NODE-{token}-{index:02d}" for index in range(22)]
    ordered = [START] + intermediate + [DESTINATION]
    graph = {}
    for index, node in enumerate(ordered):
        edges = {}
        for target_index in range(index + 1, len(ordered)):
            target = ordered[target_index]
            if target_index == index + 1:
                weight = 1 + secrets.randbelow(4)
            else:
                weight = 10000 + secrets.randbelow(1000)
            edges[target] = weight
        graph[node] = edges
    return graph


def test_fast_traversal_exists_and_is_executable():
    assert os.path.isfile(FAST_SCRIPT), f"Missing {FAST_SCRIPT}"
    assert stat.S_ISREG(os.stat(FAST_SCRIPT).st_mode), f"{FAST_SCRIPT} is not a regular file"
    assert os.access(FAST_SCRIPT, os.X_OK), f"{FAST_SCRIPT} is not executable"


def test_speedup_and_correctness():
    assert os.path.isfile(SLOW_SCRIPT), f"Missing {SLOW_SCRIPT}"
    assert os.path.isfile(FAST_SCRIPT), f"Missing {FAST_SCRIPT}"

    with open(GRAPH_FILE, "rb") as f:
        original_graph_bytes = f.read()

    with open(GRAPH_FILE, "r") as f:
        original_graph = json.load(f)

    # First verify the required result for the supplied graph and audio-derived ID.
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    run_command(["python3", FAST_SCRIPT, START], timeout=10)
    read_and_validate_result(original_graph, START)

    trusted_slow_path = "/tmp/trusted_slow_traversal.py"
    trusted_slow_result = "/tmp/trusted_slow_result.json"
    with open(trusted_slow_path, "w") as f:
        f.write(TRUSTED_SLOW)

    performance_graph = build_performance_graph()
    expected_path, expected_latency = shortest_path(performance_graph, START, DESTINATION)

    try:
        with open(GRAPH_FILE, "w") as f:
            json.dump(performance_graph, f)

        if os.path.exists(trusted_slow_result):
            os.remove(trusted_slow_result)
        slow_time = run_command(
            ["python3", trusted_slow_path, START, GRAPH_FILE, trusted_slow_result],
            timeout=120,
        )
        with open(trusted_slow_result, "r") as f:
            slow_result = json.load(f)
        assert slow_result["path"] == expected_path
        assert math.isclose(slow_result["total_latency"], expected_latency)

        if os.path.exists(RESULT_FILE):
            os.remove(RESULT_FILE)
        fast_time = run_command(["python3", FAST_SCRIPT, START], timeout=10)
        read_and_validate_result(performance_graph, START)

        speedup = slow_time / fast_time if fast_time > 0 else float("inf")
        assert speedup >= 50.0, (
            f"Speedup {speedup:.2f}x is less than required 50.0x "
            f"(Slow: {slow_time:.4f}s, Fast: {fast_time:.4f}s)"
        )
    finally:
        with open(GRAPH_FILE, "wb") as f:
            f.write(original_graph_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
