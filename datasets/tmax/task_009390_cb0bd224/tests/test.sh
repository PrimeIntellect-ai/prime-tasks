#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sys
import subprocess
import pytest

def get_truth():
    """
    Dynamically compute the expected truth values using numpy via a subprocess.
    This ensures we compute the exact expected values (including numpy's specific
    random seeding and percentiles) while strictly using only the standard library
    in the pytest execution context.
    """
    script = """
import numpy as np
import json

alpha = 0.1
Nx = 20
dx = 1.0 / Nx
x = np.linspace(0, 1, Nx + 1)
u_init = np.sin(np.pi * x)

Nt = 2
stable = False

while not stable:
    dt = 0.2 / Nt
    u = u_init.copy()

    for _ in range(Nt):
        u_new = u.copy()
        # Left domain: 1 to 9
        for i in range(1, 10):
            u_new[i] = u[i] + alpha * dt / (dx**2) * (u[i-1] - 2*u[i] + u[i+1])
        # Right domain: 11 to 19
        for i in range(11, 20):
            u_new[i] = u[i] + alpha * dt / (dx**2) * (u[i-1] - 2*u[i] + u[i+1])
        # Interface: 10
        u_new[10] = u[10] + alpha * dt / (dx**2) * (u[9] - 2*u[10] + u[11])

        u = u_new

    if np.max(u) <= 2.0:
        stable = True
    else:
        Nt *= 2

np.random.seed(42)
u_noisy = u + np.random.normal(0, 0.05, 21)
mean_noisy = np.mean(u_noisy)

np.random.seed(42)
bootstrap_means = []
for _ in range(10000):
    sample = np.random.choice(u_noisy, size=21, replace=True)
    bootstrap_means.append(np.mean(sample))

ci_lower = np.percentile(bootstrap_means, 2.5)
ci_upper = np.percentile(bootstrap_means, 97.5)

print(json.dumps({
    "stable_Nt": Nt,
    "mean_noisy": float(mean_noisy),
    "ci_lower": float(ci_lower),
    "ci_upper": float(ci_upper)
}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)

@pytest.fixture(scope="module")
def truth_data():
    return get_truth()

@pytest.fixture(scope="module")
def user_data():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Expected results file {results_path} does not exist."
    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")
    return data

def test_results_keys(user_data):
    expected_keys = {"stable_Nt", "mean_noisy", "ci_lower", "ci_upper"}
    missing = expected_keys - set(user_data.keys())
    extra = set(user_data.keys()) - expected_keys
    assert not missing, f"Missing keys in results.json: {missing}"
    assert not extra, f"Unexpected extra keys in results.json: {extra}"

def test_stable_nt(user_data, truth_data):
    assert user_data["stable_Nt"] == truth_data["stable_Nt"], (
        f"Expected stable_Nt to be {truth_data['stable_Nt']}, "
        f"but got {user_data['stable_Nt']}."
    )

def test_mean_noisy(user_data, truth_data):
    diff = abs(user_data["mean_noisy"] - truth_data["mean_noisy"])
    assert diff <= 1e-5, (
        f"mean_noisy {user_data['mean_noisy']} differs from expected "
        f"{truth_data['mean_noisy']} by {diff} (must be <= 1e-5)."
    )

def test_ci_lower(user_data, truth_data):
    diff = abs(user_data["ci_lower"] - truth_data["ci_lower"])
    assert diff <= 1e-5, (
        f"ci_lower {user_data['ci_lower']} differs from expected "
        f"{truth_data['ci_lower']} by {diff} (must be <= 1e-5)."
    )

def test_ci_upper(user_data, truth_data):
    diff = abs(user_data["ci_upper"] - truth_data["ci_upper"])
    assert diff <= 1e-5, (
        f"ci_upper {user_data['ci_upper']} differs from expected "
        f"{truth_data['ci_upper']} by {diff} (must be <= 1e-5)."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
