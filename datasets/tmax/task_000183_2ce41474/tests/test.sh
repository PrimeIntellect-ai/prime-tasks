#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_final_state():
    output_path = "/home/user/sir_ml_data_stats.json"

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    with open(output_path, "r") as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    expected_keys = {"mean_I_max", "ci_lower_95", "ci_upper_95"}
    assert set(agent_data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}. Found: {list(agent_data.keys())}"

    # Expected values derived from the deterministic random seed 42
    truth_data = {
        "mean_I_max": 513.68,
        "ci_lower_95": 501.97,
        "ci_upper_95": 524.87
    }

    for key, truth_val in truth_data.items():
        agent_val = agent_data[key]
        assert isinstance(agent_val, (int, float)), f"Value for {key} must be a float."
        # Using a tolerance of 0.5 since the exact float values are approximate in the truth
        assert abs(agent_val - truth_val) < 0.5, f"Value for {key} ({agent_val}) is too far from expected (~{truth_val})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
