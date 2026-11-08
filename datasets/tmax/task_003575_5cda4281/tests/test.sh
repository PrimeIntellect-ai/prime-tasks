#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import pytest


def test_fingerprint_mse():
    agent_file = '/home/user/fingerprint.npy'
    ref_file = '/tests/ground_truth_fingerprint.npy'

    assert os.path.isfile(agent_file), f"Agent output file is missing: {agent_file}"
    assert os.path.isfile(ref_file), f"Reference truth file is missing: {ref_file}"

    try:
        agent_arr = np.load(agent_file)
    except Exception as e:
        pytest.fail(f"Failed to load agent output file {agent_file} as a NumPy array: {e}")

    try:
        ref_arr = np.load(ref_file)
    except Exception as e:
        pytest.fail(f"Failed to load reference file {ref_file} as a NumPy array: {e}")

    assert agent_arr.shape == ref_arr.shape, f"Shape mismatch: agent array has shape {agent_arr.shape}, expected {ref_arr.shape}"

    mse = np.mean((agent_arr - ref_arr) ** 2)
    threshold = 1e-7
    assert mse < threshold, f"MSE is too high. Measured MSE: {mse}, Threshold: < {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
