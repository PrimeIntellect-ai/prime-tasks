#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import glob
import pytest

EXPECTED_DATASET = {
    "c1.json": {"id": "c1", "name": "Quantum Computing", "depends_on": ["c2", "c3"], "related_to": ["c8"]},
    "c2.json": {"id": "c2", "name": "Quantum Mechanics", "depends_on": ["c4"], "related_to": ["c3"]},
    "c3.json": {"id": "c3", "name": "Linear Algebra", "depends_on": ["c5", "c6"], "related_to": ["c4"]},
    "c4.json": {"id": "c4", "name": "Physics", "depends_on": [], "related_to": ["c2"]},
    "c5.json": {"id": "c5", "name": "Mathematics", "depends_on": [], "related_to": []},
    "c6.json": {"id": "c6", "name": "Matrix Theory", "depends_on": ["c5"], "related_to": []},
    "c7.json": {"id": "c7", "name": "String Theory", "depends_on": ["c4"], "related_to": []},
    "c8.json": {"id": "c8", "name": "Graph Theory", "depends_on": ["c5"], "related_to": []},
    "c9.json": {"id": "c9", "name": "Topology", "depends_on": ["c5"], "related_to": ["c10"]},
    "c10.json": {"id": "c10", "name": "Geometry", "depends_on": ["c5"], "related_to": ["c11"]},
    "c11.json": {"id": "c11", "name": "Manifolds", "depends_on": ["c9", "c10"], "related_to": ["c9"]},
}

def load_graph():
    paths = glob.glob("/home/user/datasets/concepts/*.json")
    actual_names = {os.path.basename(path) for path in paths}
    assert actual_names == set(EXPECTED_DATASET), "The concepts dataset was modified."

    graph = {}
    for path in paths:
        with open(path, 'r') as f:
            data = json.load(f)
        filename = os.path.basename(path)
        assert data == EXPECTED_DATASET[filename], f"Dataset file {filename} was modified."
        graph[data["id"]] = data
    return graph

def get_recursive_dependencies(graph, start_id):
    visited = set()
    queue = [start_id]

    while queue:
        current = queue.pop(0)
        for dep in graph[current]["depends_on"]:
            if dep not in visited:
                visited.add(dep)
                queue.append(dep)
    return visited

def test_dataset_integrity():
    load_graph()

def test_dependencies_txt():
    """Test the output of the recursive hierarchical querying."""
    file_path = "/home/user/dependencies.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    graph = load_graph()

    start_id = None
    for node_id, data in graph.items():
        if data["name"] == "Quantum Computing":
            start_id = node_id
            break

    assert start_id is not None, "Could not find 'Quantum Computing' in the dataset."

    dep_ids = get_recursive_dependencies(graph, start_id)
    expected_names = sorted([graph[dep_id]["name"] for dep_id in dep_ids])

    with open(file_path, 'r') as f:
        actual_names = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert actual_names == expected_names, f"Expected dependencies {expected_names}, but got {actual_names}."

def test_subgraph_json():
    """Test the output of the graph projection."""
    file_path = "/home/user/subgraph.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    graph = load_graph()

    start_id = None
    for node_id, data in graph.items():
        if data["name"] == "Quantum Computing":
            start_id = node_id
            break

    dep_ids = get_recursive_dependencies(graph, start_id)
    subgraph_ids = dep_ids | {start_id}

    expected_nodes = sorted([graph[node_id]["name"] for node_id in subgraph_ids])
    expected_edges = []

    for node_id in subgraph_ids:
        for dep_id in graph[node_id]["depends_on"]:
            if dep_id in subgraph_ids:
                expected_edges.append({
                    "source": graph[node_id]["name"],
                    "target": graph[dep_id]["name"]
                })

    expected_edges.sort(key=lambda x: (x["source"], x["target"]))

    with open(file_path, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "nodes" in actual_data, f"'nodes' missing in {file_path}"
    assert "edges" in actual_data, f"'edges' missing in {file_path}"

    assert actual_data["nodes"] == expected_nodes, f"Expected nodes {expected_nodes}, got {actual_data['nodes']}"
    assert actual_data["edges"] == expected_edges, f"Expected edges {expected_edges}, got {actual_data['edges']}"

def test_cycles_txt():
    """Test the output of the knowledge graph pattern matching."""
    file_path = "/home/user/cycles.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    graph = load_graph()
    cycles = set()

    for a in graph:
        for b in graph[a]["related_to"]:
            if b in graph:
                for c in graph[b]["related_to"]:
                    if c in graph and a in graph[c]["related_to"]:
                        if len({a, b, c}) == 3:
                            cycle_names = tuple(sorted([graph[a]["name"], graph[b]["name"], graph[c]["name"]]))
                            cycles.add(cycle_names)

    expected_lines = sorted([", ".join(cycle) for cycle in cycles])

    with open(file_path, 'r') as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Expected cycles {expected_lines}, but got {actual_lines}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
