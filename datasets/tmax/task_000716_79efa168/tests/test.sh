#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pytest


def test_solution_json_exists_and_valid():
    """Test that solution.json exists and contains the correct keys and values."""
    solution_path = "/home/user/solution.json"
    assert os.path.exists(solution_path), f"Solution file not found at {solution_path}"

    with open(solution_path, "r") as f:
        try:
            solution = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {solution_path} is not valid JSON.")

    observations = np.loadtxt("/home/user/observations.csv")
    n = observations.size
    c_mean = float(np.mean(observations))

    np.random.seed(42)
    bootstrap_samples = np.random.choice(
        observations, size=(10000, n), replace=True
    )
    bootstrap_means = np.mean(bootstrap_samples, axis=1)
    bootstrap_lower, bootstrap_upper = np.percentile(
        bootstrap_means, [2.5, 97.5]
    )

    k_value = -math.log(c_mean / 100.0) / 5.0

    np.random.seed(42)
    initial_concentrations = np.random.uniform(90.0, 110.0, 100000)
    mc_mean_c5 = float(np.mean(initial_concentrations * np.exp(-k_value * 5.0)))

    def forward_euler(dt):
        concentration = 100.0
        for _ in range(int(round(5.0 / dt))):
            concentration += dt * (-k_value * concentration)
        return concentration

    euler_diff = abs(forward_euler(0.5) - forward_euler(0.01))

    expected_values = {
        "bootstrap_lower": round(float(bootstrap_lower), 4),
        "bootstrap_upper": round(float(bootstrap_upper), 4),
        "k_value": round(k_value, 4),
        "mc_mean_c5": round(mc_mean_c5, 4),
        "euler_diff": round(euler_diff, 4),
    }

    for key, expected_val in expected_values.items():
        assert key in solution, f"Key '{key}' is missing from solution.json."
        actual_val = solution[key]
        assert isinstance(actual_val, (int, float)), f"Value for '{key}' must be a number."
        assert math.isfinite(actual_val), f"Value for '{key}' must be finite."

        diff = abs(actual_val - expected_val)
        assert diff <= 0.0002, (
            f"Value for '{key}' is {actual_val}, expected {expected_val} (±0.0002). "
            f"Difference is {diff:.6f}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
