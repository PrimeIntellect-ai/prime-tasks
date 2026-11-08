#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import math
import numpy as np
import h5py

def test_summary_json_exists():
    """Verify that the student generated the summary.json file."""
    assert os.path.isfile("/home/user/summary.json"), "The file /home/user/summary.json does not exist."

def test_summary_json_contents():
    """Verify the contents and accuracy of the summary.json file."""
    with open("/home/user/summary.json", "r") as f:
        try:
            ans = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/summary.json is not a valid JSON file."

    expected_keys = {
        "audio_rate",
        "carbon_count",
        "analytical_value",
        "bootstrap_mean",
        "bootstrap_lower",
        "bootstrap_upper"
    }
    missing_keys = expected_keys - ans.keys()
    assert not missing_keys, f"Missing keys in summary.json: {missing_keys}"

    # Recompute truth
    with h5py.File("/app/sim_results.h5", "r") as f:
        data = f["trials"][:]

    # float64 reduction
    integrals = np.trapz(data.astype(np.float64), dx=0.002, axis=1)

    np.random.seed(42)
    resamples = np.random.choice(integrals, size=(10000, 100), replace=True)
    means = np.mean(resamples, axis=1)

    target_mean = np.mean(means)
    target_lower = np.percentile(means, 2.5)
    target_upper = np.percentile(means, 97.5)

    # Check basic extracted values
    assert math.isclose(ans["audio_rate"], 0.015, rel_tol=1e-3), f"audio_rate is incorrect. Expected ~0.015, got {ans['audio_rate']}"
    assert ans["carbon_count"] == 42, f"carbon_count is incorrect. Expected 42, got {ans['carbon_count']}"
    assert math.isclose(ans["analytical_value"], 0.63, rel_tol=1e-3), f"analytical_value is incorrect. Expected ~0.63, got {ans['analytical_value']}"

    # Check statistical values
    agent_mean = float(ans["bootstrap_mean"])
    error = abs(agent_mean - target_mean)
    assert error <= 1e-4, f"bootstrap_mean error is too large. Expected {target_mean}, got {agent_mean} (error: {error} > 1e-4). Did you use float64 for the reduction?"

    agent_lower = float(ans["bootstrap_lower"])
    agent_upper = float(ans["bootstrap_upper"])

    # We allow a slightly larger tolerance for percentiles due to potential minor differences in percentile methods, 
    # but with seed 42 and exact same data, they should match closely.
    assert abs(agent_lower - target_lower) <= 1e-3, f"bootstrap_lower is incorrect. Expected ~{target_lower}, got {agent_lower}"
    assert abs(agent_upper - target_upper) <= 1e-3, f"bootstrap_upper is incorrect. Expected ~{target_upper}, got {agent_upper}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
