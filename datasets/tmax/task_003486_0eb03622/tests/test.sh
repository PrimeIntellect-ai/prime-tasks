#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np
import h5py
import pytest

def kl_divergence(p, q):
    return np.sum(p * np.log(p / q))

def test_optimized_alphas():
    alphas_path = '/home/user/solution_alphas.csv'
    assert os.path.isfile(alphas_path), f"Solution file not found at {alphas_path}"

    with h5py.File('/home/user/data/network_states.h5', 'r') as f:
        initial_dist = f['initial_dist'][:]
        target_dist = f['target_dist'][:]

    N = len(initial_dist)
    A = np.zeros((N, N))
    with open('/home/user/data/topology.txt', 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                u, v = int(parts[0]), int(parts[1])
                A[u, v] = 1.0
                A[v, u] = 1.0 

    try:
        alphas = np.loadtxt(alphas_path)
    except Exception as e:
        pytest.fail(f"Failed to load alphas from {alphas_path}: {e}")

    alphas = np.atleast_1d(np.squeeze(alphas))
    assert len(alphas) == N, f"Expected {N} alphas, got {len(alphas)}"

    x = initial_dist.copy()
    diag_alpha = np.diag(alphas)
    for _ in range(10):
        x = x + diag_alpha @ A @ x

    x_hat = x / np.sum(x)

    kl = kl_divergence(target_dist, x_hat)

    threshold = 0.005
    assert kl <= threshold, f"KL Divergence {kl:.6f} is greater than the threshold {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
