#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import numpy as np

def test_reconstruction_mse():
    """Check if /home/user/reconstruction_mse.txt contains the correct MSE."""
    path = '/home/user/reconstruction_mse.txt'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, 'r') as f:
        content = f.read().strip()

    try:
        mse_val = float(content)
    except ValueError:
        assert False, f"Content of {path} is not a valid float: '{content}'"

    X = np.loadtxt('/home/user/data.csv', delimiter=',')
    W = np.loadtxt('/home/user/weights.csv', delimiter=',')
    reconstructed = (X @ W) @ W.T
    expected_mse = round(float(np.mean((X - reconstructed) ** 2)), 4)
    assert math.isclose(mse_val, expected_mse, abs_tol=1e-4), \
        f"Expected MSE to be approximately {expected_mse}, but got {mse_val}"

def test_projected_head():
    """Check if /home/user/projected_head.csv contains the correct projected coordinates."""
    path = '/home/user/projected_head.csv'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    expected_matrix = [
        [0.8441, -0.6010, -1.7139],
        [-2.4578, 1.4939, 0.3060],
        [1.0964, 2.6963, 1.3533]
    ]

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 rows in {path}, found {len(lines)}"

    for i, line in enumerate(lines):
        parts = line.split(',')
        assert len(parts) == 3, f"Row {i+1} does not have exactly 3 columns: '{line}'"

        for j, part in enumerate(parts):
            try:
                val = float(part)
            except ValueError:
                assert False, f"Value '{part}' in row {i+1} is not a valid float."

            expected_val = expected_matrix[i][j]
            assert math.isclose(val, expected_val, abs_tol=1e-4), \
                f"Value at row {i+1}, col {j+1} expected to be {expected_val}, but got {val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
