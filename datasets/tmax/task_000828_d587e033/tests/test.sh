#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os


def test_pagerank_mae():
    """Test that the agent's PageRank scores meet the MAE threshold."""
    truth_path = "/tests/ground_truth.json"
    agent_path = "/home/user/pagerank.json"

    assert os.path.exists(truth_path), f"Truth file missing: {truth_path}"
    assert os.path.exists(agent_path), f"Agent output missing: {agent_path}"

    with open(truth_path, "r") as f:
        truth = json.load(f)

    with open(agent_path, "r") as f:
        agent = json.load(f)

    assert isinstance(truth, dict) and truth, "Ground truth JSON is empty or invalid."
    assert isinstance(agent, dict), "Agent output must be a JSON object."
    assert set(agent.keys()) == set(truth.keys()), "Agent output must contain exactly every valid entity ID."

    error_sum = 0.0
    for key in truth:
        value = agent[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"Score for {key} is not numeric."
        assert math.isfinite(value), f"Score for {key} is not finite."
        error_sum += abs(truth[key] - value)

    mae = error_sum / len(truth)
    threshold = 0.0001
    assert mae <= threshold, f"MAE {mae} exceeds threshold {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
