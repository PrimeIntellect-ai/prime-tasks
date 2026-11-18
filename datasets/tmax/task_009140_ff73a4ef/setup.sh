#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user/ml_data
    cd /home/user/ml_data

    cat << 'EOF' > generate_data.py
import numpy as np

def generate_and_solve(N, seed, X_file, Y_file, expected_file, iters, lr):
    np.random.seed(seed)
    X = np.random.rand(N, 3)
    W_true = np.array([[1.5, -0.5, 0.2], [0.1, 1.0, 0.8], [-0.5, 0.0, 1.2]])
    Y = X @ W_true + np.random.randn(N, 3) * 0.05

    np.savetxt(X_file, X, fmt="%.6f")
    np.savetxt(Y_file, Y, fmt="%.6f")

    W = np.zeros((3, 3))
    for _ in range(iters):
        grad = (2.0 / N) * X.T @ (X @ W - Y)
        W -= lr * grad

    if expected_file:
        np.savetxt(expected_file, W, fmt="%.6f")

generate_and_solve(20, 42, "test_X.txt", "test_Y.txt", "test_W_expected.txt", 2000, 0.05)
generate_and_solve(100, 99, "train_X.txt", "train_Y.txt", "expected_final_W.txt", 2000, 0.05)
EOF

    python3 generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
