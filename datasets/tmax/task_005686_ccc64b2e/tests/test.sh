#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

EXPECTED_DATASETS = [
    {"id": "D1", "derived_from": [], "schema_fields": ["id", "timestamp", "value", "source"]},
    {"id": "D2", "derived_from": ["D1"], "schema_fields": ["id", "timestamp", "notes"]},
    {"id": "D3", "derived_from": ["D2"], "schema_fields": ["id", "value", "source", "meta"]},
    {"id": "D4", "derived_from": ["D3"], "schema_fields": ["id", "meta", "author"]},
    {"id": "D5", "derived_from": ["D4", "D9"], "schema_fields": ["value", "notes"]},
    {"id": "D6", "derived_from": ["D7"], "schema_fields": ["id", "log"]},
    {"id": "D7", "derived_from": ["D8"], "schema_fields": ["timestamp", "log"]},
    {"id": "D8", "derived_from": ["D6"], "schema_fields": ["id", "source"]},
    {"id": "D9", "derived_from": ["D1"], "schema_fields": ["timestamp", "author"]},
    {"id": "D10", "derived_from": ["D5"], "schema_fields": ["id", "timestamp", "value", "source", "meta"]}
]

def get_datasets():
    file_path = "/home/user/datasets.json"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    with open(file_path, "r") as f:
        datasets = json.load(f)
    assert datasets == EXPECTED_DATASETS, f"The supplied dataset metadata in {file_path} was modified."
    return datasets

def compute_expected_cycle(datasets):
    graph = {d["id"]: d["derived_from"] for d in datasets}

    def find_cycle():
        visited = set()
        rec_stack = set()
        cycle_nodes = set()

        def dfs(node, path):
            visited.add(node)
            rec_stack.add(node)
            path.append(node)

            for neighbor in graph.get(node, []):
                if neighbor not in visited:
                    if dfs(neighbor, path):
                        return True
                elif neighbor in rec_stack:
                    cycle_start = path.index(neighbor)
                    for n in path[cycle_start:]:
                        cycle_nodes.add(n)
                    return True

            rec_stack.remove(node)
            path.pop()
            return False

        for node in graph:
            if node not in visited:
                if dfs(node, []):
                    return sorted(list(cycle_nodes))
        return []

    return ",".join(find_cycle())

def compute_expected_depth(datasets, target="D10"):
    graph = {d["id"]: d["derived_from"] for d in datasets}
    memo = {}

    def get_depth(node):
        if node in memo:
            return memo[node]

        parents = graph.get(node, [])
        if not parents:
            return 0

        max_d = 0
        for p in parents:
            max_d = max(max_d, 1 + get_depth(p))

        memo[node] = max_d
        return max_d

    return get_depth(target)

def compute_expected_schemas(datasets, target="D1"):
    d1_fields = set()
    for d in datasets:
        if d["id"] == target:
            d1_fields = set(d["schema_fields"])
            break

    similar = []
    for d in datasets:
        if d["id"] == target:
            continue
        shared = set(d["schema_fields"]).intersection(d1_fields)
        if len(shared) >= 2:
            similar.append(d["id"])

    return sorted(similar)

def test_cycle_detection():
    datasets = get_datasets()
    expected_cycle = compute_expected_cycle(datasets)

    cycle_file = "/home/user/cycle.txt"
    assert os.path.exists(cycle_file), f"Missing {cycle_file}"

    with open(cycle_file, "r") as f:
        actual_cycle = f.read().strip()

    assert actual_cycle == expected_cycle, f"Expected cycle '{expected_cycle}', but got '{actual_cycle}'"

def test_hierarchical_depth():
    datasets = get_datasets()
    expected_depth = compute_expected_depth(datasets)

    depth_file = "/home/user/depth.txt"
    assert os.path.exists(depth_file), f"Missing {depth_file}"

    with open(depth_file, "r") as f:
        actual_depth = f.read().strip()

    assert actual_depth == str(expected_depth), f"Expected depth {expected_depth}, but got {actual_depth}"

def test_schema_analysis():
    datasets = get_datasets()
    expected_similar = compute_expected_schemas(datasets)

    schemas_file = "/home/user/similar_schemas.txt"
    assert os.path.exists(schemas_file), f"Missing {schemas_file}"

    with open(schemas_file, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_similar, f"Expected similar schemas {expected_similar}, but got {actual_lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
