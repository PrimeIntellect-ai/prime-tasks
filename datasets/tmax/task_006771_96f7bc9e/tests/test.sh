#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

SCRIPT_PATH = "/home/user/get_top_centrality.py"
RESULT_PATH = "/home/user/result.json"
EDGES_PATH = "/home/user/data/edges.json"
NODES_PATH = "/home/user/data/nodes.json"

def test_script_exists():
    """Check if the student's script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

def test_script_execution_k3():
    """Run the script with K=3 and verify the output."""
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    result = subprocess.run(
        ["python3", SCRIPT_PATH, "3"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"
    assert os.path.isfile(RESULT_PATH), f"Output file {RESULT_PATH} was not created."

    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {RESULT_PATH} is not valid JSON.")

    assert isinstance(data, list), "Result should be a JSON array."
    assert len(data) == 3, f"Expected 3 results, got {len(data)}."

    expected_k3 = [
        {"node_id": "N1", "degree_centrality": 5, "name": "Alpha", "cluster": "C1"},
        {"node_id": "N2", "degree_centrality": 4, "name": "Bravo", "cluster": "C1"},
        {"node_id": "N3", "degree_centrality": 3, "name": "Charlie", "cluster": "C2"}
    ]

    assert data == expected_k3, f"Result data does not match expected output for K=3. Got: {data}"

def test_script_execution_k5():
    """Run the script with K=5 to ensure it's not hardcoded."""
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    result = subprocess.run(
        ["python3", SCRIPT_PATH, "5"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"
    assert os.path.isfile(RESULT_PATH), f"Output file {RESULT_PATH} was not created."

    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {RESULT_PATH} is not valid JSON.")

    assert isinstance(data, list), "Result should be a JSON array."
    assert len(data) == 5, f"Expected 5 results, got {len(data)}."

    expected_k5 = [
        {"node_id": "N1", "degree_centrality": 5, "name": "Alpha", "cluster": "C1"},
        {"node_id": "N2", "degree_centrality": 4, "name": "Bravo", "cluster": "C1"},
        {"node_id": "N3", "degree_centrality": 3, "name": "Charlie", "cluster": "C2"},
        {"node_id": "N4", "degree_centrality": 2, "name": "Delta", "cluster": "C2"},
        {"node_id": "N5", "degree_centrality": 2, "name": "Echo", "cluster": "C3"}
    ]

    assert data == expected_k5, f"Result data does not match expected output for K=5. Got: {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
