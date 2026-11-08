#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import subprocess
import random
import uuid
from collections import deque
import pytest

BINARY_PATH = "/home/user/deadlock_analyzer/target/release/deadlock_analyzer"


def load_edges(path):
    edges = []
    with open(path, "r") as f:
        for line in f:
            parts = line.rstrip("\n").split(",")
            if len(parts) >= 2:
                edges.append((parts[0], parts[1]))
    return edges


def shortest_cycle(edges, target):
    adjacency = {}
    for waiting, holding in edges:
        adjacency.setdefault(waiting, []).append(holding)

    queue = deque([(target, [target])])
    visited = {target}
    while queue:
        node, path = queue.popleft()
        for neighbor in adjacency.get(node, []):
            if neighbor == target:
                return path
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, path + [neighbor]))
    return None


def read_json_array(path):
    with open(path, "r") as f:
        value = json.load(f)
    assert isinstance(value, list), f"Output in {path} is not a JSON array"
    assert all(isinstance(item, str) for item in value), f"Output in {path} must contain only strings"
    return value


def run_analyzer(input_path, target, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run(
        [BINARY_PATH, input_path, target, output_path],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Binary execution failed with code {result.returncode}. Stderr: {result.stderr}"
    )
    assert os.path.exists(output_path), f"Output JSON not generated at {output_path}"
    return read_json_array(output_path)


def test_local_correctness():
    """Check the supplied output and freshly execute the analyzer on the sample data."""
    assert os.path.exists("/app/cycle.json"), "Missing /app/cycle.json. Did you run the binary on /app/locks.csv?"

    try:
        data = read_json_array("/app/cycle.json")
    except Exception as e:
        pytest.fail(f"Failed to parse /app/cycle.json: {e}")

    expected = ["TX_88192", "TX_11111", "TX_22222", "TX_33333"]
    assert data == expected, f"Incorrect cycle found on sample data. Expected {expected}, got {data}"

    assert os.path.exists(BINARY_PATH), f"Release binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"

    derived = shortest_cycle(load_edges("/app/locks.csv"), "TX_88192")
    assert derived is not None, "No cycle containing TX_88192 exists in /app/locks.csv"
    assert data == derived, f"/app/cycle.json is not the shortest cycle derived from /app/locks.csv: {derived}"

    fresh = run_analyzer("/app/locks.csv", "TX_88192", "/tmp/local_recheck.json")
    assert fresh == data, "Fresh analyzer output for /app/locks.csv differs from /app/cycle.json"


def test_randomized_correctness_and_shortest_cycle():
    """Use undisclosed randomized IDs and change the graph while retaining the same target."""
    target = "TX_TARGET_" + uuid.uuid4().hex

    def node(label):
        return f"TX_{label}_{uuid.uuid4().hex}"

    # First graph has a unique three-node shortest cycle and a longer decoy cycle.
    a, b = node("A"), node("B")
    c, d, e = node("C"), node("D"), node("E")
    u, v, w = node("U"), node("V"), node("W")
    edges1 = [
        (target, c), (c, d), (d, e), (e, target),
        (target, a), (a, b), (b, target),
        (u, v), (v, w), (w, u),
        (a, u), (d, v),
    ]
    random.SystemRandom().shuffle(edges1)

    path1 = "/tmp/random_graph_one.csv"
    with open(path1, "w") as f:
        for waiting, holding in edges1:
            f.write(f"{waiting},{holding},1690000000\n")

    expected1 = shortest_cycle(load_edges(path1), target)
    assert expected1 == [target, a, b]
    actual1 = run_analyzer(path1, target, "/tmp/random_graph_one.json")
    assert actual1 == expected1, f"Expected randomized shortest cycle {expected1}, got {actual1}"

    # Reuse the exact target with different data and a different shortest cycle.
    x = node("X")
    p, q, r = node("P"), node("Q"), node("R")
    m, n = node("M"), node("N")
    edges2 = [
        (target, p), (p, q), (q, r), (r, target),
        (target, x), (x, target),
        (m, n), (n, m),
        (p, m),
    ]
    random.SystemRandom().shuffle(edges2)

    path2 = "/tmp/random_graph_two.csv"
    with open(path2, "w") as f:
        for waiting, holding in edges2:
            f.write(f"{waiting},{holding},1690000000\n")

    expected2 = shortest_cycle(load_edges(path2), target)
    assert expected2 == [target, x]
    actual2 = run_analyzer(path2, target, "/tmp/random_graph_two.json")
    assert actual2 == expected2, f"Expected randomized shortest cycle {expected2}, got {actual2}"
    assert actual2 != actual1, "Analyzer output did not change when the input graph changed"


def test_hidden_dataset_performance():
    """Verify performance and correctness on a 2-million edge hidden graph."""
    binary_path = "/home/user/deadlock_analyzer/target/release/deadlock_analyzer"
    assert os.path.exists(binary_path), f"Release binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"

    hidden_csv = "/tmp/hidden_locks.csv"
    hidden_out = "/tmp/hidden_out.json"

    # Generate hidden dataset (2 million edges)
    # We use IDs from 100000 to 999999 to ensure we don't accidentally create a shorter cycle for TX_99999
    with open(hidden_csv, 'w') as f:
        for _ in range(200):
            chunk = []
            for _ in range(10000):
                w = f"TX_{random.randint(100000, 999999)}"
                h = f"TX_{random.randint(100000, 999999)}"
                chunk.append(f"{w},{h},1690000000\n")
            f.writelines(chunk)

        # Add the known shortest cycle
        cycle = ["TX_99999", "TX_A", "TX_B", "TX_C", "TX_D"]
        for i in range(len(cycle)):
            f.write(f"{cycle[i]},{cycle[(i+1)%len(cycle)]},1690000000\n")

    # Run benchmark
    start_time = time.time()
    res = subprocess.run([binary_path, hidden_csv, "TX_99999", hidden_out], capture_output=True, text=True)
    end_time = time.time()

    assert res.returncode == 0, f"Binary execution failed with code {res.returncode}. Stderr: {res.stderr}"

    runtime = end_time - start_time

    assert os.path.exists(hidden_out), f"Hidden output JSON not generated at {hidden_out}"
    try:
        with open(hidden_out, "r") as f:
            hidden_data = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to parse {hidden_out}: {e}")

    expected_cycle = ["TX_99999", "TX_A", "TX_B", "TX_C", "TX_D"]
    assert hidden_data == expected_cycle, f"Incorrect cycle on hidden data. Expected {expected_cycle}, got {hidden_data}"

    assert runtime < 0.5, f"Execution time {runtime:.3f}s exceeded threshold of 0.5s"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
