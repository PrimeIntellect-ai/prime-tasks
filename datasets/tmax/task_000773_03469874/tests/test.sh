#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest


def test_top_backups_output():
    output_path = '/home/user/top_backups.json'
    assert os.path.isfile(output_path), f"Output file not found at {output_path}"

    try:
        with open(output_path, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to load output JSON: {e}")

    expected = [
        {"node": "B", "score": 56.25},
        {"node": "D", "score": 38.333333333333336},
        {"node": "A", "score": 37.916666666666664},
        {"node": "E", "score": 25.0},
        {"node": "C", "score": 24.125}
    ]

    assert isinstance(agent_data, list), "Output must be a JSON array"
    assert len(agent_data) == 5, f"Expected 5 items in the output, got {len(agent_data)}"

    max_error = 0.0
    for i in range(5):
        agent_node = agent_data[i].get("node")
        expected_node = expected[i]["node"]
        assert agent_node == expected_node, f"Node mismatch at index {i}: expected '{expected_node}', got '{agent_node}'"

        agent_score = agent_data[i].get("score")
        assert isinstance(agent_score, (int, float)), f"Score for node {agent_node} must be a number"

        expected_score = expected[i]["score"]
        error = abs(agent_score - expected_score)
        if error > max_error:
            max_error = error

    threshold = 0.1
    assert max_error <= threshold, f"MAE {max_error} exceeds threshold {threshold}"
TEST_EOF

if [ -f /home/user/backup_analyzer/Cargo.toml ] \
   && rm -f /home/user/top_backups.json \
   && timeout 120s cargo run --quiet --manifest-path /home/user/backup_analyzer/Cargo.toml \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
