#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pytest
from scipy.stats import wasserstein_distance

def test_notebook_exists():
    path = "/home/user/fit_spectra.ipynb"
    assert os.path.isfile(path), f"The required notebook {path} is missing."

def test_lmfit_setup_cfg_fixed():
    path = "/app/lmfit-1.2.2/setup.cfg"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "numpy==1.9.0" not in content, f"The setup.cfg still requires numpy==1.9.0. It must be fixed to allow installation."

def test_fitted_y_exists():
    path = "/home/user/fitted_y.npy"
    assert os.path.isfile(path), f"The output file {path} is missing."

def test_fitted_y_wasserstein_distance():
    truth_path = "/tests/truth_norm.npy"
    agent_path = "/home/user/fitted_y.npy"

    assert os.path.isfile(truth_path), f"Truth file {truth_path} is missing."
    assert os.path.isfile(agent_path), f"Agent file {agent_path} is missing."

    y_true_norm = np.load(truth_path)
    y_agent_norm = np.load(agent_path)

    assert y_true_norm.shape == y_agent_norm.shape, f"Shape mismatch: truth is {y_true_norm.shape}, agent is {y_agent_norm.shape}"

    # x coordinates are uniformly spaced 0 to 100
    x = np.linspace(0, 100, 500)

    # Calculate Earth Mover's distance treating the normalized spectra as PDF weights
    dist = wasserstein_distance(x, x, u_weights=y_agent_norm, v_weights=y_true_norm)

    threshold = 0.05
    assert dist <= threshold, f"Wasserstein distance {dist:.5f} exceeds threshold {threshold}. The fit is not accurate enough."

def test_fitted_y_normalized():
    agent_path = "/home/user/fitted_y.npy"
    assert os.path.isfile(agent_path), f"Agent file {agent_path} is missing."

    y_agent_norm = np.load(agent_path)
    # Check if it sums to 1.0 (with small tolerance for float precision)
    total_sum = np.sum(y_agent_norm)
    assert np.isclose(total_sum, 1.0, atol=1e-4), f"The fitted intensity array is not properly normalized. Sum is {total_sum:.5f}, expected 1.0"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
