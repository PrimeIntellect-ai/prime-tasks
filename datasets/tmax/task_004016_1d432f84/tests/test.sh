#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import numpy as np
import pytest

def test_best_params_mse():
    params_file = "/home/user/best_params.txt"
    assert os.path.isfile(params_file), f"Missing required file: {params_file}"

    with open(params_file, "r") as f:
        content = f.read().strip()

    params = content.split(",")
    assert len(params) == 3, f"Expected 3 comma-separated parameters in {params_file}, but found {len(params)}. Content: '{content}'"

    # Ground truth data generator for the evaluator
    t = np.linspace(0, 10, 100)
    # True params: alpha=0.5, beta=10.0, gamma=2.0
    true_y = 10.0 * np.exp(-0.5 * t) * np.cos(2.0 * t)

    # Run simulator
    cmd = ["/app/sim_model", params[0], params[1], params[2]]
    try:
        out = subprocess.check_output(cmd, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run simulator with parameters {params}: {e}")

    lines = out.strip().split('\n')[1:] # skip header
    assert len(lines) == 100, f"Expected 100 lines of output from simulator, got {len(lines)}"

    try:
        sim_y = np.array([float(line.split(',')[1]) for line in lines])
    except Exception as e:
        pytest.fail(f"Failed to parse simulator output: {e}")

    mse = np.mean((true_y - sim_y)**2)
    threshold = 0.05

    assert mse < threshold, f"MSE {mse:.5f} is not below the threshold of {threshold}. Parameters used: {params}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
