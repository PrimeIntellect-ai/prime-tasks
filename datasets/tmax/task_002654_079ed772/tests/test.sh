#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import secrets
import subprocess

import pytest

SOURCE = "/home/user/analyze_routing.cpp"
BINARY = "/home/user/analyze_routing"
NODES = "/home/user/nodes.json"
EDGES = "/home/user/edges.json"
RESULT = "/home/user/result.json"


def run_program():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}. "
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT), "The C++ program did not create /home/user/result.json."


def read_result():
    try:
        with open(RESULT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{RESULT} is not a valid JSON file.")
    except Exception as exc:
        pytest.fail(f"Could not read {RESULT}: {exc}")


def expected_result(nodes, edges):
    loads = {node["id"]: node["load"] for node in nodes}
    graph = {node_id: [] for node_id in loads}
    for edge in edges:
        graph.setdefault(edge["src"], []).append((edge["dst"], edge["latency"]))

    distances = {"Gateway": 0}
    paths = {"Gateway": ["Gateway"]}
    queue = [(0, "Gateway")]
    while queue:
        distance, current = heapq.heappop(queue)
        if distance != distances.get(current):
            continue
        if current == "Database":
            break
        for destination, latency in graph.get(current, []):
            candidate = distance + latency
            if candidate < distances.get(destination, float("inf")):
                distances[destination] = candidate
                paths[destination] = paths[current] + [destination]
                heapq.heappush(queue, (candidate, destination))

    path = paths["Database"]
    return {
        "path": path,
        "total_latency": distances["Database"],
        "total_load": sum(loads[node_id] for node_id in path),
    }


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SOURCE), "/home/user/analyze_routing.cpp does not exist."
    with open(NODES, "rb") as f:
        original_nodes = f.read()
    with open(EDGES, "rb") as f:
        original_edges = f.read()

    compiled = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, (
        f"Failed to compile {SOURCE}. stdout: {compiled.stdout}\nstderr: {compiled.stderr}"
    )

    run_program()
    try:
        yield
    finally:
        with open(NODES, "wb") as f:
            f.write(original_nodes)
        with open(EDGES, "wb") as f:
            f.write(original_edges)
        try:
            run_program()
        except Exception:
            pass


def test_result_json_exists():
    """Check that the result.json file was created."""
    assert os.path.isfile(RESULT), "/home/user/result.json does not exist. The C++ program may not have run or failed to output."


def test_result_json_content():
    """Check that result.json contains the correct shortest path and aggregations."""
    data = read_result()

    assert "path" in data, "The 'path' key is missing from result.json."
    assert "total_latency" in data, "The 'total_latency' key is missing from result.json."
    assert "total_load" in data, "The 'total_load' key is missing from result.json."

    expected_path = ["Gateway", "Router1", "Database"]
    expected_latency = 25
    expected_load = 85

    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
    assert data["total_latency"] == expected_latency, f"Expected total_latency {expected_latency}, but got {data['total_latency']}."
    assert data["total_load"] == expected_load, f"Expected total_load {expected_load}, but got {data['total_load']}."


def test_program_computes_additional_fixtures():
    rng = secrets.SystemRandom()
    suffix = secrets.token_hex(5)

    a = f"Alpha_{suffix}"
    b = f"Beta_{suffix}"
    c = f"Core_{suffix}"
    first_nodes = [
        {"id": "Gateway", "load": rng.randint(3, 40)},
        {"id": a, "load": rng.randint(3, 40)},
        {"id": b, "load": rng.randint(3, 40)},
        {"id": c, "load": rng.randint(3, 40)},
        {"id": "Database", "load": rng.randint(3, 40)},
    ]
    w1, w2, w3 = (rng.randint(1, 7) for _ in range(3))
    best = w1 + w2 + w3
    first_edges = [
        {"src": "Gateway", "dst": a, "latency": w1},
        {"src": a, "dst": c, "latency": w2},
        {"src": c, "dst": "Database", "latency": w3},
        {"src": "Gateway", "dst": b, "latency": 2},
        {"src": b, "dst": "Database", "latency": best + 11},
        {"src": "Gateway", "dst": "Database", "latency": best + 19},
        {"src": b, "dst": a, "latency": best + 5},
        {"src": c, "dst": "Gateway", "latency": 1},
    ]

    x = f"Relay_{secrets.token_hex(5)}"
    y = f"Spare_{secrets.token_hex(5)}"
    direct = rng.randint(2, 8)
    second_nodes = [
        {"id": "Gateway", "load": rng.randint(41, 90)},
        {"id": x, "load": rng.randint(41, 90)},
        {"id": y, "load": rng.randint(41, 90)},
        {"id": "Database", "load": rng.randint(41, 90)},
    ]
    second_edges = [
        {"src": "Gateway", "dst": "Database", "latency": direct},
        {"src": "Gateway", "dst": x, "latency": direct + 3},
        {"src": x, "dst": "Database", "latency": 1},
        {"src": "Gateway", "dst": y, "latency": direct + 7},
        {"src": y, "dst": x, "latency": 2},
        {"src": x, "dst": "Gateway", "latency": 1},
    ]

    for nodes, edges in [(first_nodes, first_edges), (second_nodes, second_edges)]:
        expected = expected_result(nodes, edges)
        with open(NODES, "w") as f:
            json.dump(nodes, f)
        with open(EDGES, "w") as f:
            json.dump(edges, f)

        run_program()
        actual = read_result()
        assert "path" in actual, "The 'path' key is missing from result.json."
        assert "total_latency" in actual, "The 'total_latency' key is missing from result.json."
        assert "total_load" in actual, "The 'total_load' key is missing from result.json."
        assert actual["path"] == expected["path"], f"Expected path {expected['path']}, but got {actual['path']}."
        assert actual["total_latency"] == expected["total_latency"], (
            f"Expected total_latency {expected['total_latency']}, but got {actual['total_latency']}."
        )
        assert actual["total_load"] == expected["total_load"], (
            f"Expected total_load {expected['total_load']}, but got {actual['total_load']}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
