#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import numpy as np
import scipy.integrate as integrate
from scipy.linalg import expm

def get_truth():
    np.random.seed(42)

    Q0 = np.array([
        [-0.84, 0.21, 0.42, 0.21],
        [0.18, -0.75, 0.27, 0.30],
        [0.45, 0.15, -0.90, 0.30],
        [0.12, 0.48, 0.24, -0.84]
    ])

    def f(t):
        return np.exp(-0.1 * t) * (np.cos(t)**2)

    def S(T):
        if T == 0:
            val = 0.0
        else:
            val, _ = integrate.quad(f, 0, T)
        R_T = Q0 * val
        P_T = expm(R_T)
        I = np.eye(4)
        return np.linalg.norm(P_T - I, ord='fro')

    def log_likelihood(T, S_obs=1.25, sigma=0.1):
        if T < 0 or T > 10:
            return -np.inf
        s_t = S(T)
        return -0.5 * ((S_obs - s_t) / sigma)**2

    T_current = 1.0
    samples = []
    ll_current = log_likelihood(T_current)

    for i in range(5000):
        T_prop = np.random.normal(T_current, 0.5)
        ll_prop = log_likelihood(T_prop)

        if np.log(np.random.uniform(0, 1)) < (ll_prop - ll_current):
            T_current = T_prop
            ll_current = ll_prop

        samples.append(T_current)

    post_burn = np.array(samples[1000:])

    boot_medians = []
    for _ in range(1000):
        resample = np.random.choice(post_burn, size=len(post_burn), replace=True)
        boot_medians.append(np.median(resample))

    ci_lower = np.percentile(boot_medians, 2.5)
    ci_upper = np.percentile(boot_medians, 97.5)

    return round(ci_lower, 3), round(ci_upper, 3)

def test_results_json_exists_and_valid():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"File {results_path} does not exist. Ensure your script saves the output."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    assert "ci_lower" in results, "Key 'ci_lower' missing from results.json"
    assert "ci_upper" in results, "Key 'ci_upper' missing from results.json"

    assert isinstance(results["ci_lower"], (int, float)), "'ci_lower' must be a number."
    assert isinstance(results["ci_upper"], (int, float)), "'ci_upper' must be a number."

def test_results_accuracy():
    results_path = "/home/user/results.json"
    if not os.path.isfile(results_path):
        pytest.skip("results.json not found, skipping accuracy test.")

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("results.json is not valid JSON, skipping accuracy test.")

    if "ci_lower" not in results or "ci_upper" not in results:
        pytest.skip("Missing keys in results.json, skipping accuracy test.")

    ci_lower_student = results["ci_lower"]
    ci_upper_student = results["ci_upper"]

    ci_lower_truth, ci_upper_truth = get_truth()

    # We allow a tolerance of 0.2 to account for minor differences in RNG usage or MCMC implementations
    assert abs(ci_lower_student - ci_lower_truth) < 0.2, f"ci_lower {ci_lower_student} is not within acceptable tolerance of expected {ci_lower_truth}"
    assert abs(ci_upper_student - ci_upper_truth) < 0.2, f"ci_upper {ci_upper_student} is not within acceptable tolerance of expected {ci_upper_truth}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
