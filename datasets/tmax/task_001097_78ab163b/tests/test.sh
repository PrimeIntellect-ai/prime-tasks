#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

# We import numpy because it is strictly required to read .npy files and validate the math.
try:
    import numpy as np
except ImportError:
    pytest.fail("numpy is required for this test but is not installed.")

def test_notebook_exists_and_valid():
    notebook_path = '/home/user/fit_models.ipynb'
    assert os.path.isfile(notebook_path), f"Notebook {notebook_path} does not exist."

    with open(notebook_path, 'r', encoding='utf-8') as f:
        try:
            nb = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Notebook {notebook_path} is not a valid JSON file.")

    assert "cells" in nb, f"Notebook {notebook_path} is not a valid Jupyter Notebook (missing 'cells')."

def test_weights_correctness():
    weights_path = '/home/user/weights.npy'
    assert os.path.isfile(weights_path), f"Weights file {weights_path} does not exist."

    X_path = '/home/user/X_data.npy'
    y_path = '/home/user/y_data.npy'

    assert os.path.isfile(X_path), f"Input file {X_path} is missing."
    assert os.path.isfile(y_path), f"Input file {y_path} is missing."

    X = np.load(X_path)
    y = np.load(y_path)

    try:
        weights = np.load(weights_path)
    except Exception as e:
        pytest.fail(f"Failed to load {weights_path}: {e}")

    K, N, M = X.shape
    expected_weights = np.zeros((K, M))

    # Recompute the expected weights using the exact truncated SVD logic
    for i in range(K):
        U, S, Vt = np.linalg.svd(X[i], full_matrices=False)
        S_inv = np.zeros_like(S)
        # Truncation threshold: strictly less than 1e-4 treated as zero
        valid_sv = S >= 1e-4
        S_inv[valid_sv] = 1.0 / S[valid_sv]

        X_pinv = Vt.T @ np.diag(S_inv) @ U.T
        expected_weights[i] = X_pinv @ y[i]

    assert weights.shape == expected_weights.shape, f"Expected weights shape {expected_weights.shape}, got {weights.shape}."

    if not np.allclose(weights, expected_weights, atol=1e-5):
        pytest.fail("The computed weights do not match the expected weights. Ensure you applied the truncated SVD correctly with the 1e-4 threshold.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
