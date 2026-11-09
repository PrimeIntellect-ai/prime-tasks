#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sys
import subprocess
import math
import pytest

def get_expected_results():
    """
    Computes the expected results using a subprocess to avoid importing 
    third-party libraries directly in the test file, adhering to stdlib-only rules.
    """
    script = """
import h5py
import numpy as np
from scipy.stats import wasserstein_distance, bootstrap
import json

with h5py.File("/home/user/sim_data.h5", "r") as f:
    valid_indices = []
    final_values = []

    for i in range(100):
        t = f[f"sim_{i}/t"][:]
        y = f[f"sim_{i}/y"][:]

        y_true = np.exp(-0.5 * t)
        w_dist = wasserstein_distance(y, y_true)

        if w_dist < 0.05:
            valid_indices.append(i)
            final_values.append(y[-1])

    valid_indices.sort()

    res = bootstrap((final_values,), np.mean, confidence_level=0.95, n_resamples=1000, method='BCa', random_state=42)

    expected_output = {
        "valid_indices": valid_indices,
        "mean_ci_lower": float(res.confidence_interval.low),
        "mean_ci_upper": float(res.confidence_interval.high)
    }

    print(json.dumps(expected_output))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected results. Ensure h5py and scipy are installed.\nError: {result.stderr}")

    return json.loads(result.stdout)

def test_results_file_exists():
    """Check that the results.json file exists."""
    file_path = "/home/user/results.json"
    assert os.path.exists(file_path), f"File missing: {file_path}"
    assert os.path.isfile(file_path), f"Expected a file, but found something else at: {file_path}"

def test_results_format_and_values():
    """Check that the results.json file contains the correct keys and values."""
    file_path = "/home/user/results.json"

    with open(file_path, "r") as f:
        try:
            student_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_results = get_expected_results()

    # Check keys
    expected_keys = {"valid_indices", "mean_ci_lower", "mean_ci_upper"}
    assert set(student_results.keys()) == expected_keys, f"JSON keys do not match. Expected {expected_keys}, got {set(student_results.keys())}"

    # Check valid_indices
    assert isinstance(student_results["valid_indices"], list), "valid_indices must be a list"
    assert student_results["valid_indices"] == expected_results["valid_indices"], f"valid_indices do not match expected values."

    # Check bounds (allow small floating point tolerance)
    assert isinstance(student_results["mean_ci_lower"], (int, float)), "mean_ci_lower must be a number"
    assert isinstance(student_results["mean_ci_upper"], (int, float)), "mean_ci_upper must be a number"

    assert math.isclose(student_results["mean_ci_lower"], expected_results["mean_ci_lower"], rel_tol=1e-5), \
        f"mean_ci_lower is incorrect. Expected approx {expected_results['mean_ci_lower']}, got {student_results['mean_ci_lower']}"

    assert math.isclose(student_results["mean_ci_upper"], expected_results["mean_ci_upper"], rel_tol=1e-5), \
        f"mean_ci_upper is incorrect. Expected approx {expected_results['mean_ci_upper']}, got {student_results['mean_ci_upper']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
