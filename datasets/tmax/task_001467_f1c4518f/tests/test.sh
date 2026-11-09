#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import random
import subprocess
import pytest

def test_mcmc_sim_fixed():
    path = "/home/user/mcmc_sim.py"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "math.fsum(" in content, "The script /home/user/mcmc_sim.py does not use math.fsum as requested."
    assert "sum(" not in content.replace("math.fsum(", ""), "The standard sum() function is still being used in /home/user/mcmc_sim.py."

def test_posterior_samples():
    path = "/home/user/posterior.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    # Generate expected samples deterministically
    random.seed(42)
    data = [1e16, 2.5, -1e16, 3.5, 1e16, -1e16, 1.2, -1e16, 1e16]
    data_sum = math.fsum(data)  # exactly 7.2

    mu_current = 0.0
    expected_samples = []
    for _ in range(5000):
        mu_proposal = mu_current + random.gauss(0, 1.0)
        log_prob_current = -0.5 * (mu_current - data_sum)**2
        log_prob_proposal = -0.5 * (mu_proposal - data_sum)**2
        accept_prob = math.exp(min(0.0, log_prob_proposal - log_prob_current))
        if random.random() < accept_prob:
            mu_current = mu_proposal
        expected_samples.append(mu_current)

    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 5000, f"Expected 5000 samples in {path}, got {len(lines)}."

    for i, (actual_str, expected_val) in enumerate(zip(lines, expected_samples)):
        actual_val = float(actual_str)
        assert math.isclose(actual_val, expected_val, rel_tol=1e-9), f"Sample {i} mismatch: expected {expected_val}, got {actual_val}."

def test_p_value_correct():
    path = "/home/user/p_value.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    # Calculate the expected p-value using a subprocess to avoid third-party imports in the test suite
    script = """
import numpy as np
from scipy.stats import ks_2samp

posterior = np.loadtxt('/home/user/posterior.txt')
ground_truth = np.loadtxt('/home/user/ground_truth.txt')
expected_ks = ks_2samp(posterior, ground_truth)
print(f"{expected_ks.pvalue:.4f}")
"""
    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to compute expected p-value: {result.stderr}"

    expected_p = result.stdout.strip()

    with open(path, "r") as f:
        actual_p = f.read().strip()

    assert actual_p == expected_p, f"Expected p-value {expected_p} in {path}, got {actual_p}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
