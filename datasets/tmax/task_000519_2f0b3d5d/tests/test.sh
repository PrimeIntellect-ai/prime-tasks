#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_profile_results_exists():
    """Test that the results JSON file exists."""
    results_path = "/home/user/profile_results.json"
    assert os.path.exists(results_path), f"Results file {results_path} does not exist."
    assert os.path.isfile(results_path), f"Results path {results_path} is not a file."

def test_profile_results_content():
    """Test that the results JSON contains the correct keys and values."""
    results_path = "/home/user/profile_results.json"
    data_path = "/home/user/data.npy"

    assert os.path.exists(results_path), f"Missing {results_path}"
    assert os.path.exists(data_path), f"Missing {data_path}"

    try:
        import numpy as np
    except ImportError:
        pytest.fail("numpy is not installed, cannot verify computations.")

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected_keys = {"max_abs_error", "svd_vt0_abs_sum", "boot_ci_lower", "boot_ci_upper"}
    assert set(results.keys()) == expected_keys, f"Expected keys {expected_keys}, got {set(results.keys())}"

    # Compute expected results
    data = np.load(data_path)
    data_reshaped = data.reshape(100, 2500)

    errors = []
    for j in range(2500):
        col = data_reshaped[:, j]

        # Unstable sum
        s = np.float32(0.0)
        for val in col:
            s += val

        # Stable sum
        stable_s = math.fsum(col)

        errors.append(float(s) - stable_s)

    errors = np.array(errors)
    max_abs_error = float(np.max(np.abs(errors)))

    U, S, Vt = np.linalg.svd(data_reshaped, full_matrices=False)
    vt0_abs_sum = float(np.sum(np.abs(Vt[0])))

    np.random.seed(42)
    means = []
    for _ in range(1000):
        sample = np.random.choice(errors, size=len(errors), replace=True)
        means.append(np.mean(sample))

    boot_ci_lower = float(np.percentile(means, 2.5))
    boot_ci_upper = float(np.percentile(means, 97.5))

    # Assert values
    assert math.isclose(results["max_abs_error"], max_abs_error, rel_tol=1e-4), \
        f"max_abs_error expected ~{max_abs_error}, got {results['max_abs_error']}"

    assert math.isclose(results["svd_vt0_abs_sum"], vt0_abs_sum, rel_tol=1e-4), \
        f"svd_vt0_abs_sum expected ~{vt0_abs_sum}, got {results['svd_vt0_abs_sum']}"

    assert math.isclose(results["boot_ci_lower"], boot_ci_lower, rel_tol=1e-4), \
        f"boot_ci_lower expected ~{boot_ci_lower}, got {results['boot_ci_lower']}"

    assert math.isclose(results["boot_ci_upper"], boot_ci_upper, rel_tol=1e-4), \
        f"boot_ci_upper expected ~{boot_ci_upper}, got {results['boot_ci_upper']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
