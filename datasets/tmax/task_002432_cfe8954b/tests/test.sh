#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
from collections import deque

import pytest

C_SOURCE = "/home/user/shortest_path.c"
PIPELINE = "/home/user/pipeline.sh"
OUTPUT = "/home/user/path_output.json"
NODES = "/home/user/data/nodes.csv"
EDGES = "/home/user/data/edges.csv"
C_BINARY = f"/tmp/shortest_path_verifier_{os.getpid()}"


def run(cmd, timeout=20):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)


def shortest_distance(edges, start, end):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)
    distances = {start: 0}
    queue = deque([start])
    while queue:
        node = queue.popleft()
        if node == end:
            return distances[node]
        for neighbor in adjacency.get(node, []):
            if neighbor not in distances:
                distances[neighbor] = distances[node] + 1
                queue.append(neighbor)
    return None


def validate_id_path(path, edges, start, end):
    assert path, "Path output is empty"
    assert path[0] == start, f"Path starts at {path[0]}, not {start}"
    assert path[-1] == end, f"Path ends at {path[-1]}, not {end}"
    edge_set = set(edges)
    for pair in zip(path, path[1:]):
        assert pair in edge_set, f"Path uses nonexistent directed edge {pair}"
    expected = shortest_distance(edges, start, end)
    assert expected is not None
    assert len(path) - 1 == expected, (
        f"Path has {len(path) - 1} edges, but shortest distance is {expected}"
    )


def write_graph(nodes, edges):
    with open(NODES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name"])
        writer.writerows(nodes)
    with open(EDGES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target"])
        writer.writerows(edges)


def test_00_execute_required_pipeline_for_original_query():
    result = run(["bash", PIPELINE, "1", "7"], timeout=30)
    assert result.returncode == 0, (
        f"pipeline.sh 1 7 failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_c_program_exists():
    assert os.path.isfile(C_SOURCE), "/home/user/shortest_path.c is missing"


def test_bash_script_exists():
    assert os.path.isfile(PIPELINE), "/home/user/pipeline.sh is missing"


def test_json_output_exists_and_valid():
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is missing. Did you run pipeline.sh 1 7?"

    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT} does not contain valid JSON.")

    assert "path" in data, "'path' key missing in JSON output"
    assert "length" in data, "'length' key missing in JSON output"
    assert data["length"] == 3, f"Expected length 3, got {data['length']}"

    expected_path = [
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"},
        {"id": 3, "name": "Charlie"},
        {"id": 7, "name": "Grace"},
    ]
    actual_path = data["path"]
    assert len(actual_path) == 4, (
        f"Expected path of length 4 nodes, got {len(actual_path)}"
    )
    for i, expected_node in enumerate(expected_path):
        assert int(actual_path[i]["id"]) == expected_node["id"], (
            f"Expected node id {expected_node['id']} at position {i}"
        )
        assert actual_path[i]["name"] == expected_node["name"], (
            f"Expected node name {expected_node['name']} at position {i}"
        )


def test_c_program_compiles_and_solves_unseen_graphs(tmp_path):
    compiled = run(["gcc", "-std=c11", "-O2", C_SOURCE, "-o", C_BINARY], timeout=30)
    assert compiled.returncode == 0, (
        f"shortest_path.c did not compile\nstdout:\n{compiled.stdout}"
        f"\nstderr:\n{compiled.stderr}"
    )

    rng = random.SystemRandom()
    for case in range(3):
        ids = rng.sample(range(20, 990), 8)
        start, a, b, end, x, y, z, isolated = ids
        edges = [
            (start, a), (a, b), (b, end),
            (start, x), (x, y), (y, z), (z, end),
            (a, x), (isolated, start),
        ]
        rng.shuffle(edges)
        graph = tmp_path / f"edges_{case}_{secrets.token_hex(4)}.csv"
        with open(graph, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["source", "target"])
            writer.writerows(edges)

        result = run([C_BINARY, str(graph), str(start), str(end)])
        assert result.returncode == 0, (
            f"C program failed on generated graph\nstdout:\n{result.stdout}"
            f"\nstderr:\n{result.stderr}"
        )
        assert result.stdout.strip() != "NO_PATH", "C program reported NO_PATH incorrectly"
        try:
            path = [int(value) for value in result.stdout.split()]
        except ValueError:
            pytest.fail(f"C output is not a space-separated ID path: {result.stdout!r}")
        validate_id_path(path, edges, start, end)

    no_path_ids = rng.sample(range(20, 990), 4)
    start, middle, end, other = no_path_ids
    graph = tmp_path / f"no_path_{secrets.token_hex(4)}.csv"
    with open(graph, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target"])
        writer.writerows([(start, middle), (end, other)])
    result = run([C_BINARY, str(graph), str(start), str(end)])
    assert result.returncode == 0, f"C program failed on no-path graph: {result.stderr}"
    assert result.stdout.strip() == "NO_PATH", (
        f"Expected NO_PATH, got {result.stdout!r}"
    )


def test_pipeline_processes_unseen_data_and_maps_names():
    with open(NODES, "rb") as f:
        original_nodes = f.read()
    with open(EDGES, "rb") as f:
        original_edges = f.read()

    rng = random.SystemRandom()
    ids = rng.sample(range(30, 980), 9)
    start, a, b, end, x, y, z, q, r = ids
    names = {node_id: f"User_{secrets.token_hex(5)}" for node_id in ids}
    edges = [
        (start, a), (a, b), (b, end),
        (start, x), (x, y), (y, z), (z, end),
        (a, q), (q, r), (r, z),
    ]
    node_rows = list(names.items())
    rng.shuffle(node_rows)
    rng.shuffle(edges)

    try:
        write_graph(node_rows, edges)
        result = run(["bash", PIPELINE, str(start), str(end)], timeout=30)
        assert result.returncode == 0, (
            f"pipeline failed on generated data\nstdout:\n{result.stdout}"
            f"\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT), "pipeline did not create path_output.json"
        with open(OUTPUT) as f:
            data = json.load(f)

        assert isinstance(data, dict)
        assert "path" in data, "'path' key missing in generated JSON"
        assert "length" in data, "'length' key missing in generated JSON"
        assert isinstance(data["path"], list), "'path' must be a JSON array"
        assert isinstance(data["length"], int) and not isinstance(data["length"], bool), (
            "'length' must be an integer"
        )

        path_ids = []
        for node in data["path"]:
            assert isinstance(node, dict), "Each path entry must be a JSON object"
            assert "id" in node and "name" in node
            assert isinstance(node["id"], int) and not isinstance(node["id"], bool), (
                "Path IDs must be JSON integers"
            )
            assert node["id"] in names, f"Unknown node ID {node['id']}"
            assert node["name"] == names[node["id"]], (
                f"Incorrect name for node {node['id']}"
            )
            path_ids.append(node["id"])

        validate_id_path(path_ids, edges, start, end)
        assert data["length"] == len(path_ids) - 1, (
            "JSON length is not the number of edges in the path"
        )
    finally:
        with open(NODES, "wb") as f:
            f.write(original_nodes)
        with open(EDGES, "wb") as f:
            f.write(original_edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
