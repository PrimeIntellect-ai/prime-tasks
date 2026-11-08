#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import math
import os
import random
import subprocess
import time

import pytest


def load_and_validate_results(path, queries):
    assert os.path.isfile(path), f"Output JSON file {path} was not created."
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to parse output JSON: {e}")

    assert isinstance(data, list), "Output JSON should be a list of objects."
    assert len(data) == len(queries), f"Expected {len(queries)} results, but got {len(data)}."

    for i, (item, (src, dst)) in enumerate(zip(data, queries)):
        assert isinstance(item, dict), f"Result {i} is not an object."
        assert set(item) == {"src", "dst", "cost"}, f"Result {i} must contain exactly src, dst, and cost."
        assert isinstance(item["src"], int) and not isinstance(item["src"], bool), f"Result {i} has invalid src."
        assert isinstance(item["dst"], int) and not isinstance(item["dst"], bool), f"Result {i} has invalid dst."
        assert item["src"] == src and item["dst"] == dst, f"Result {i} does not match its query."
        assert isinstance(item["cost"], (int, float)) and not isinstance(item["cost"], bool), f"Result {i} has invalid cost."
        assert math.isfinite(float(item["cost"])), f"Result {i} has a non-finite cost."
    return data


def test_query_engine_performance():
    init_graph_path = "/home/user/init_graph.csv"
    assert os.path.isfile(init_graph_path), f"Missing {init_graph_path}. You must extract the initial graph from the image."

    engine_path = "/home/user/query_engine"
    assert os.path.isfile(engine_path), f"Missing {engine_path}. You must compile your C program to this path."
    assert os.access(engine_path, os.X_OK), f"{engine_path} is not executable."
    with open(engine_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{engine_path} must be a compiled executable."

    random.seed(42)
    large_updates_path = "/tmp/large_updates.csv"
    with open(large_updates_path, "w") as f:
        for _ in range(50000):
            action = random.choice(["ADD", "UPD", "DEL"])
            src = random.randint(1, 1000)
            dst = random.randint(1, 1000)
            cost = round(random.uniform(1.0, 100.0), 1)
            f.write(f"{action},{src},{dst},{cost}\n")

    large_queries_path = "/tmp/large_queries.csv"
    queries = []
    with open(large_queries_path, "w") as f:
        for _ in range(5000):
            src = random.randint(1, 1000)
            dst = random.randint(1, 1000)
            queries.append((src, dst))
            f.write(f"{src},{dst}\n")

    out_json_path = "/tmp/out.json"
    if os.path.exists(out_json_path):
        os.remove(out_json_path)

    start = time.time()
    result = subprocess.run(
        [engine_path, init_graph_path, large_updates_path, large_queries_path, out_json_path],
        capture_output=True,
        text=True
    )
    duration = time.time() - start

    assert result.returncode == 0, f"query_engine failed with return code {result.returncode}.\nstderr: {result.stderr}"
    load_and_validate_results(out_json_path, queries)

    threshold = 0.5
    assert duration <= threshold, f"Execution time {duration:.4f}s exceeded threshold {threshold}s. Your implementation must be further optimized."


def test_init_graph_extraction():
    init_graph_path = "/home/user/init_graph.csv"
    assert os.path.isfile(init_graph_path), f"Missing {init_graph_path}."

    rows = []
    with open(init_graph_path, newline="") as f:
        for line_no, row in enumerate(csv.reader(f), 1):
            assert len(row) == 3, f"Line {line_no} must have exactly three comma-separated fields."
            try:
                rows.append((int(row[0]), int(row[1]), float(row[2])))
            except ValueError:
                pytest.fail(f"Line {line_no} contains invalid edge data or a header.")

    expected = [
        (1, 2, 5.0),
        (1, 3, 2.0),
        (3, 2, 1.5),
        (2, 4, 4.0),
        (3, 4, 8.0),
        (4, 5, 3.0),
    ]
    assert rows == expected, "init_graph.csv does not exactly contain the complete table extracted from the image."


def shortest_costs(edges, queries):
    adjacency = {}
    for (src, dst), cost in edges.items():
        adjacency.setdefault(src, []).append((dst, cost))

    by_source = {}
    for src, _ in queries:
        if src in by_source:
            continue
        dist = {src: 0.0}
        heap = [(0.0, src)]
        while heap:
            current, node = heapq.heappop(heap)
            if current != dist.get(node):
                continue
            for nxt, weight in adjacency.get(node, ()): 
                candidate = current + weight
                if candidate < dist.get(nxt, float("inf")):
                    dist[nxt] = candidate
                    heapq.heappush(heap, (candidate, nxt))
        by_source[src] = dist
    return [by_source[src].get(dst, -1.0) for src, dst in queries]


def make_correctness_case(prefix):
    rng = random.SystemRandom()
    init_path = prefix + "_init.csv"
    updates_path = prefix + "_updates.csv"
    queries_path = prefix + "_queries.csv"
    output_path = prefix + "_output.json"

    edges = {}
    initial = []
    for base in (0, 40):
        for i in range(40):
            src = base + i
            dst = base + ((i + 1) % 40)
            cost = rng.randint(10, 200) / 10.0
            edges[(src, dst)] = cost
            initial.append((src, dst, cost))

    while len(initial) < 260:
        base = rng.choice((0, 40))
        src = base + rng.randrange(40)
        dst = base + rng.randrange(40)
        if src != dst and (src, dst) not in edges:
            cost = rng.randint(10, 300) / 10.0
            edges[(src, dst)] = cost
            initial.append((src, dst, cost))

    with open(init_path, "w") as f:
        for src, dst, cost in initial:
            f.write(f"{src},{dst},{cost:.1f}\n")

    updates = []
    for i in range(240):
        action = ("UPD", "DEL", "ADD")[i % 3]
        if action == "UPD":
            src, dst = rng.choice(list(edges.keys()))
            cost = rng.randint(5, 350) / 10.0
            edges[(src, dst)] = cost
        elif action == "DEL":
            src, dst = rng.choice(list(edges.keys()))
            cost = 0.0
            del edges[(src, dst)]
        else:
            while True:
                base = rng.choice((0, 40))
                src = base + rng.randrange(40)
                dst = base + rng.randrange(40)
                if src != dst and (src, dst) not in edges:
                    break
            cost = rng.randint(5, 350) / 10.0
            edges[(src, dst)] = cost
        updates.append((action, src, dst, cost))

    with open(updates_path, "w") as f:
        for action, src, dst, cost in updates:
            f.write(f"{action},{src},{dst},{cost:.1f}\n")

    queries = [(i, i) for i in range(0, 80, 7)]
    queries += [(rng.randrange(40), 40 + rng.randrange(40)) for _ in range(30)]
    queries += [(rng.randrange(80), rng.randrange(80)) for _ in range(260)]
    with open(queries_path, "w") as f:
        for src, dst in queries:
            f.write(f"{src},{dst}\n")

    return init_path, updates_path, queries_path, output_path, queries, shortest_costs(edges, queries)


def assert_engine_correct(engine, prefix):
    init_path, updates_path, queries_path, output_path, queries, expected = make_correctness_case(prefix)
    result = subprocess.run(
        [engine, init_path, updates_path, queries_path, output_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"query engine failed correctness test.\nstderr: {result.stderr}"
    actual = load_and_validate_results(output_path, queries)
    for i, (item, wanted) in enumerate(zip(actual, expected)):
        got = float(item["cost"])
        assert math.isclose(got, wanted, rel_tol=1e-6, abs_tol=1e-6), \
            f"Incorrect shortest-path cost for query {i} {queries[i]}: got {got}, expected {wanted}."


def test_computed_shortest_path_costs():
    source_path = "/home/user/query_engine.c"
    assert os.path.isfile(source_path), f"Missing {source_path}."

    rebuilt = "/tmp/query_engine_rebuilt"
    build = subprocess.run(
        ["gcc", "-O3", source_path, "-o", rebuilt, "-lm"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"query_engine.c did not compile.\nstderr: {build.stderr}"

    assert_engine_correct("/home/user/query_engine", "/tmp/delivered_case")
    assert_engine_correct(rebuilt, "/tmp/rebuilt_case")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
