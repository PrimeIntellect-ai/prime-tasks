#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_profiling_report_exists():
    """Check that the output JSON file exists."""
    file_path = "/home/user/profiling_report.json"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_profiling_report_structure_and_values():
    """Check the structure and values of the profiling report."""
    file_path = "/home/user/profiling_report.json"

    with open(file_path, 'r') as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "polyfit_coefficients" in res, "Missing 'polyfit_coefficients' in JSON."
    assert "wasserstein_distance" in res, "Missing 'wasserstein_distance' in JSON."

    agent_coeffs = res["polyfit_coefficients"]
    agent_w_dist = res["wasserstein_distance"]

    assert isinstance(agent_coeffs, list), "'polyfit_coefficients' must be a list."
    assert len(agent_coeffs) == 3, "'polyfit_coefficients' must have exactly 3 elements."
    assert isinstance(agent_w_dist, float), "'wasserstein_distance' must be a float."

    # Expected values derived from the deterministic data generation
    expected_coeffs = [0.99222588, -0.00392398, 0.00010903]
    expected_w_dist = 0.00010724606990278775

    for i, (agent_val, expected_val) in enumerate(zip(agent_coeffs, expected_coeffs)):
        assert math.isclose(agent_val, expected_val, rel_tol=1e-4, abs_tol=1e-5), \
            f"Coefficient {i} mismatch: expected {expected_val}, got {agent_val}"

    assert math.isclose(agent_w_dist, expected_w_dist, rel_tol=1e-4, abs_tol=1e-5), \
        f"Wasserstein distance mismatch: expected {expected_w_dist}, got {agent_w_dist}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
