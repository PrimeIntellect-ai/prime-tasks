#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_alice_team_json_exists_and_valid():
    output_path = '/home/user/alice_team.json'
    assert os.path.exists(output_path), f"File {output_path} does not exist. The task requires exporting the result to this path."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except Exception as e:
            pytest.fail(f"Failed to parse JSON from {output_path}: {e}")

    assert "nodes" in data, "JSON output is missing the 'nodes' key."
    assert "edges" in data, "JSON output is missing the 'edges' key."

def test_alice_team_nodes():
    output_path = '/home/user/alice_team.json'
    with open(output_path, 'r') as f:
        data = json.load(f)

    expected_nodes = sorted(["Alice", "Bob", "Charlie", "David", "Eve", "Frank", "Grace", "Harry", "Isabella", "Jack"])
    nodes = data.get("nodes", [])

    assert isinstance(nodes, list), "'nodes' must be a list."
    assert nodes == expected_nodes, f"Nodes mismatch. Expected {expected_nodes}, but got {nodes}."

def test_alice_team_edges():
    output_path = '/home/user/alice_team.json'
    with open(output_path, 'r') as f:
        data = json.load(f)

    expected_edges = sorted([
        {"manager": "Alice", "employee": "Bob"},
        {"manager": "Alice", "employee": "Charlie"},
        {"manager": "Bob", "employee": "David"},
        {"manager": "Charlie", "employee": "Eve"},
        {"manager": "David", "employee": "Frank"},
        {"manager": "David", "employee": "Harry"},
        {"manager": "Eve", "employee": "Grace"},
        {"manager": "Eve", "employee": "Isabella"},
        {"manager": "Isabella", "employee": "Jack"}
    ], key=lambda x: (x["manager"], x["employee"]))

    edges = data.get("edges", [])

    assert isinstance(edges, list), "'edges' must be a list."
    assert edges == expected_edges, f"Edges mismatch. Expected {expected_edges}, but got {edges}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
