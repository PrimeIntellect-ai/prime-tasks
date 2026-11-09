#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import h5py
import numpy as np
import pytest

def test_recovered_signal_mse():
    target_file = '/home/user/recovered_signal.h5'
    assert os.path.exists(target_file), f"Target file {target_file} does not exist."

    try:
        with h5py.File(target_file, 'r') as f:
            assert 'true_signal' in f, f"Dataset 'true_signal' not found in {target_file}."
            recovered = f['true_signal'][:]
    except Exception as e:
        pytest.fail(f"Failed to read {target_file}: {e}")

    # Recompute ground truth
    freq = np.linspace(0, 100, 1000)
    true_signal = 5.0 * np.exp(-((freq - 20)**2)/10) + \
                  3.0 * np.exp(-((freq - 50)**2)/5) + \
                  4.0 * np.exp(-((freq - 80)**2)/8)

    assert recovered.shape == true_signal.shape, \
        f"Shape mismatch: expected {true_signal.shape}, got {recovered.shape}"

    mse = np.mean((recovered - true_signal)**2)
    assert mse < 0.05, f"MSE {mse:.6f} is not less than the required threshold of 0.05."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
