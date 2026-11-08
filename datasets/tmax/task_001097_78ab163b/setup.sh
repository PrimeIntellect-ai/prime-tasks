#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy jupyter papermill

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

np.random.seed(42)
K, N, M = 5, 50, 10

X = np.zeros((K, N, M))
y = np.zeros((K, N))

for i in range(K):
    # Create random matrix
    A = np.random.randn(N, M)
    U, S_orig, Vt = np.linalg.svd(A, full_matrices=False)

    # Artificially modify singular values to include ones below 1e-4
    S = np.linspace(1, 0.00005, M) 
    # For dataset i, make the last (i+1) singular values very small
    S[-(i+1):] = 1e-5

    X[i] = U @ np.diag(S) @ Vt

    # True weights
    w_true = np.random.randn(M)
    y[i] = X[i] @ w_true + np.random.randn(N) * 0.1

np.save('/home/user/X_data.npy', X)
np.save('/home/user/y_data.npy', y)

# Pre-calculate the expected weights for verification
expected_weights = np.zeros((K, M))
for i in range(K):
    U, S, Vt = np.linalg.svd(X[i], full_matrices=False)
    S_inv = np.zeros_like(S)
    S_inv[S >= 1e-4] = 1.0 / S[S >= 1e-4]
    X_pinv = Vt.T @ np.diag(S_inv) @ U.T
    expected_weights[i] = X_pinv @ y[i]

np.save('/home/user/expected_weights.npy', expected_weights)
os.chmod('/home/user/X_data.npy', 0o644)
os.chmod('/home/user/y_data.npy', 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
