#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pytest

def test_reconstructed_noise_mse():
    target_file = '/home/user/reconstructed_noise.npy'
    truth_file = '/tests/ground_truth_noise.npy'

    assert os.path.isfile(target_file), f"Agent's output file is missing: {target_file}"
    assert os.path.isfile(truth_file), f"Ground truth file is missing: {truth_file}"

    try:
        predicted = np.load(target_file)
    except Exception as e:
        pytest.fail(f"Failed to load the agent's output as a numpy array. Error: {e}")

    try:
        truth = np.load(truth_file)
    except Exception as e:
        pytest.fail(f"Failed to load the ground truth numpy array. Error: {e}")

    assert predicted.shape == truth.shape, (
        f"Agent's reconstructed matrix has incorrect shape. "
        f"Expected {truth.shape}, got {predicted.shape}."
    )

    mse = np.mean((predicted - truth) ** 2)
    threshold = 1e-4

    assert mse <= threshold, (
        f"MSE {mse:.6e} is greater than the allowed threshold {threshold:.6e}. "
        f"The reconstructed noise matrix is not accurate enough."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
