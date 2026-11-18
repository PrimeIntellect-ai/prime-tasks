#!/bin/bash
mkdir -p /logs/verifier
reward=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
import time
from collections import Counter, defaultdict

import pytest

PROJECT = "/home/user/kg_engine"
BINARY = "/home/user/kg_engine/target/release/kg_engine"
EDGES = "/home/user/data/edges.csv"
RESULTS = "/home/user/results.json"


def expected_from_csv(path):
    adjacency = defaultdict(set)
    out_degree = Counter()

    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source", "target"], "edges.csv must have source,target headers"
        for row in reader:
            source = int(row["source"])
            target = int(row["target"])
            adjacency[source].add(target)
            out_degree[source] += 1

    triangle_nodes = set()
    for source, targets in adjacency.items():
        for middle in targets:
            for target in adjacency.get(middle, ()):
                if source in adjacency.get(target, ()):
                    triangle_nodes.update((source, middle, target))

    return sorted(triangle_nodes, key=lambda node: (-out_degree[node], node))[:5]


def run_engine_and_load():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    started = time.monotonic()
    try:
        completed = subprocess.run(
            [BINARY],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The release program did not execute the entire pipeline in under 2 seconds.")
    elapsed = time.monotonic() - started

    assert completed.returncode == 0, (
        f"The release program exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert elapsed < 2.0, f"The release program took {elapsed:.3f} seconds, exceeding 2 seconds."
    assert os.path.isfile(RESULTS), (
        f"The file {RESULTS} does not exist. The Rust program may not have created it."
    )

    with open(RESULTS) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS} does not contain valid JSON.")

    assert isinstance(data, list), (
        f"The JSON in {RESULTS} should be a list, but got {type(data).__name__}."
    )
    assert all(type(node) is int for node in data), "Every result must be a JSON integer."
    return data


def write_unpredictable_graph(path):
    rng = secrets.SystemRandom()
    nodes = rng.sample(range(100_000, 900_000), 7)
    triangle_nodes = nodes[:6]
    decoy = nodes[6]
    edges = set()

    # Two disjoint directed triangles.
    edges.update([
        (triangle_nodes[0], triangle_nodes[1]),
        (triangle_nodes[1], triangle_nodes[2]),
        (triangle_nodes[2], triangle_nodes[0]),
        (triangle_nodes[3], triangle_nodes[4]),
        (triangle_nodes[4], triangle_nodes[5]),
        (triangle_nodes[5], triangle_nodes[3]),
    ])

    # Give triangle participants differing whole-graph out-degrees, including a tie.
    extra_counts = [15, 12, 12, 8, 6, 4]
    leaf = rng.randrange(2_000_000, 3_000_000)
    for source, count in zip(triangle_nodes, extra_counts):
        for _ in range(count):
            edges.add((source, leaf))
            leaf += 1

    # A high-degree node not in any triangle must not appear in the result.
    for _ in range(40):
        edges.add((decoy, leaf))
        leaf += 1

    edge_list = list(edges)
    random.SystemRandom().shuffle(edge_list)
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target"])
        writer.writerows(edge_list)


def test_compiled_engine_computes_results():
    assert os.path.isfile(os.path.join(PROJECT, "src/main.rs")), "src/main.rs is missing."
    assert os.path.isfile(BINARY), "cargo build --release did not produce the kg_engine binary."
    assert os.access(BINARY, os.X_OK), "The release artifact is not executable."

    original_edges = open(EDGES, "rb").read()
    original_results = None
    try:
        expected = expected_from_csv(EDGES)
        data = run_engine_and_load()

        # Preserve the original verifier's exact expected-result assertion.
        hardcoded_expected = [20, 99, 10, 30, 100]
        assert data == hardcoded_expected, (
            f"The results in {RESULTS} are incorrect. Expected {hardcoded_expected}, but got {data}."
        )
        assert data == expected, f"The engine output does not match the graph-derived answer {expected}."
        original_results = open(RESULTS, "rb").read()

        # Re-run on unpredictable input so a prewritten results.json cannot pass.
        write_unpredictable_graph(EDGES)
        changed_expected = expected_from_csv(EDGES)
        assert len(changed_expected) == 5
        changed_data = run_engine_and_load()
        assert changed_data == changed_expected, (
            f"On the verification graph, expected {changed_expected}, but got {changed_data}."
        )
    finally:
        with open(EDGES, "wb") as f:
            f.write(original_edges)
        if original_results is not None:
            with open(RESULTS, "wb") as f:
                f.write(original_results)
TEST_EOF

if timeout 180 cargo build --release --manifest-path /home/user/kg_engine/Cargo.toml >/tmp/kg_build.log 2>&1; then
    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        reward=1
    else
        cat /tmp/kg_build.log
    fi
else
    cat /tmp/kg_build.log
fi

echo "$reward" > /logs/verifier/reward.txt
