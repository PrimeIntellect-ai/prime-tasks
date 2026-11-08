#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np

def test_estimated_means_mse():
    """Test that the estimated means are saved and have an MSE <= 0.01 compared to the true means."""
    target_file = '/home/user/estimated_means.txt'
    assert os.path.exists(target_file), f"File not found: {target_file}"

    try:
        estimated = np.loadtxt(target_file)
        # Ensure it's a 1D array
        estimated = np.atleast_1d(estimated).flatten()
    except Exception as e:
        assert False, f"Error reading {target_file}: {e}"

    assert len(estimated) == 3, f"Expected exactly 3 means, found {len(estimated)}."

    estimated = np.sort(estimated)
    true_means = np.array([1.25, 2.80, 4.15])

    mse = np.mean((estimated - true_means) ** 2)

    assert mse <= 0.01, f"MSE of estimated means is {mse:.6f}, which is greater than the threshold of 0.01. Estimated means: {estimated}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
