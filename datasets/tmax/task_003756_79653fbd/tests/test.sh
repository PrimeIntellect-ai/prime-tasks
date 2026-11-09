#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import secrets
import subprocess

import pytest

PROJECT = "/home/user/graph_optimizer"
DATA_DIR = "/home/user/data"
OUTPUT = "/home/user/results/optimized_paths.csv"
BINARY = os.path.join(PROJECT, "target", "release", "graph_optimizer")

ORIGINAL_NODES = [
    {"id": "A", "delay": 2},
    {"id": "B", "delay": 5},
    {"id": "C", "delay": 1},
    {"id": "D", "delay": 0},
    {"id": "E", "delay": 3},
    {"id": "F", "delay": 10},
]
ORIGINAL_EDGES = [
    {"source": "A", "target": "B", "cost": 10},
    {"source": "A", "target": "C", "cost": 2},
    {"source": "C", "target": "B", "cost": 3},
    {"source": "B", "target": "D", "cost": 5},
    {"source": "C", "target": "D", "cost": 12},
    {"source": "D", "target": "E", "cost": 2},
    {"source": "E", "target": "F", "cost": 1},
    {"source": "C", "target": "F", "cost": 20},
]
ORIGINAL_QUERIES = [
    {"query_id": "q1", "start": "A", "end": "E"},
    {"query_id": "q2", "start": "A", "end": "F"},
    {"query_id": "q3", "start": "C", "end": "D"},
]


def write_inputs(nodes, edges, queries):
    os.makedirs(DATA_DIR, exist_ok=True)
    for name, value in (("nodes.json", nodes), ("edges.json", edges), ("queries.json", queries)):
        with open(os.path.join(DATA_DIR, name), "w") as f:
            json.dump(value, f)


def run_binary():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([BINARY], cwd=PROJECT, check=True, timeout=30)
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} is missing after running the Rust utility."


def read_csv():
    with open(OUTPUT, "r", newline="") as f:
        reader = csv.DictReader(f)
        expected_fields = ["query_id", "path", "total_cost", "total_delay"]
        assert reader.fieldnames is not None, "CSV file is empty or missing headers."
        assert [field.strip() for field in reader.fieldnames] == expected_fields, \
            f"CSV headers do not match. Expected {expected_fields}, got {reader.fieldnames}"
        return [{k.strip(): v.strip() for k, v in row.items()} for row in reader]


@pytest.fixture(scope="session", autouse=True)
def build_and_run_project():
    assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT, check=True, capture_output=True, text=True, timeout=30
    )
    metadata = json.loads(metadata_result.stdout)
    assert any(package.get("name") == "graph_optimizer" for package in metadata.get("packages", [])), \
        "The Cargo package must be named graph_optimizer."

    if os.path.exists(BINARY):
        os.remove(BINARY)
    subprocess.run(["cargo", "build", "--release"], cwd=PROJECT, check=True, timeout=180)
    assert os.path.isfile(BINARY), f"Release executable {BINARY} was not produced."
    assert os.access(BINARY, os.X_OK), f"Release artifact {BINARY} is not executable."

    write_inputs(ORIGINAL_NODES, ORIGINAL_EDGES, ORIGINAL_QUERIES)
    run_binary()
    yield
    write_inputs(ORIGINAL_NODES, ORIGINAL_EDGES, ORIGINAL_QUERIES)
    run_binary()


def test_optimized_paths_csv_exists():
    file_path = "/home/user/results/optimized_paths.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."


def test_optimized_paths_csv_content():
    file_path = "/home/user/results/optimized_paths.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    expected_rows = [
        {"query_id": "q1", "path": "A->C->B->D->E", "total_cost": "12", "total_delay": "11"},
        {"query_id": "q2", "path": "A->C->B->D->E->F", "total_cost": "13", "total_delay": "21"},
        {"query_id": "q3", "path": "C->B->D", "total_cost": "8", "total_delay": "6"},
    ]

    with open(file_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        expected_fields = ["query_id", "path", "total_cost", "total_delay"]
        assert reader.fieldnames is not None, "CSV file is empty or missing headers."
        assert [field.strip() for field in reader.fieldnames] == expected_fields, \
            f"CSV headers do not match. Expected {expected_fields}, got {reader.fieldnames}"

        rows = list(reader)
        assert len(rows) == len(expected_rows), \
            f"Expected {len(expected_rows)} rows of data, but found {len(rows)}."

        for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
            actual_clean = {k.strip(): v.strip() for k, v in actual.items()}
            assert actual_clean == expected, \
                f"Row {i + 1} does not match expected output.\nExpected: {expected}\nActual: {actual_clean}"


def derive_expected(nodes, edges, queries):
    delays = {node["id"]: node["delay"] for node in nodes}
    graph = {node_id: [] for node_id in delays}
    for edge in edges:
        graph.setdefault(edge["source"], []).append((edge["target"], edge["cost"]))

    answers = []
    for query in queries:
        start, end = query["start"], query["end"]
        queue = [(0, start, [start])]
        best = {start: 0}
        result = None
        while queue:
            cost, node, path = heapq.heappop(queue)
            if cost != best.get(node):
                continue
            if node == end:
                result = (cost, path)
                break
            for target, edge_cost in graph.get(node, []):
                new_cost = cost + edge_cost
                if new_cost < best.get(target, float("inf")):
                    best[target] = new_cost
                    heapq.heappush(queue, (new_cost, target, path + [target]))
        assert result is not None
        cost, path = result
        answers.append({
            "query_id": query["query_id"],
            "path": "->".join(path),
            "total_cost": str(cost),
            "total_delay": str(sum(delays[node] for node in path)),
        })
    return answers


def test_program_reads_inputs_and_computes_shortest_paths():
    token = secrets.token_hex(5)
    s, a, b, c, t = [f"{token}_{name}" for name in ("start", "alpha", "beta", "center", "target")]
    x = 2 + secrets.randbelow(8)
    y = 2 + secrets.randbelow(8)
    z = 2 + secrets.randbelow(8)

    nodes = [
        {"id": s, "delay": 1 + secrets.randbelow(20)},
        {"id": a, "delay": 1 + secrets.randbelow(20)},
        {"id": b, "delay": 1 + secrets.randbelow(20)},
        {"id": c, "delay": 1 + secrets.randbelow(20)},
        {"id": t, "delay": 1 + secrets.randbelow(20)},
    ]
    edges = [
        {"source": s, "target": a, "cost": x},
        {"source": a, "target": c, "cost": y},
        {"source": c, "target": t, "cost": z},
        {"source": s, "target": b, "cost": x + y + 5},
        {"source": b, "target": c, "cost": 1},
        {"source": a, "target": t, "cost": y + z + 7},
        {"source": b, "target": t, "cost": z + 8},
        {"source": s, "target": t, "cost": x + y + z + 20},
    ]
    queries = [
        {"query_id": f"{token}_q1", "start": s, "end": t},
        {"query_id": f"{token}_q2", "start": b, "end": t},
        {"query_id": f"{token}_q3", "start": a, "end": t},
        {"query_id": f"{token}_q4", "start": s, "end": c},
    ]
    expected = derive_expected(nodes, edges, queries)

    try:
        write_inputs(nodes, edges, queries)
        run_binary()
        actual = read_csv()
        assert actual == expected, f"Output for verifier-generated inputs is incorrect.\nExpected: {expected}\nActual: {actual}"
    finally:
        write_inputs(ORIGINAL_NODES, ORIGINAL_EDGES, ORIGINAL_QUERIES)
        run_binary()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
