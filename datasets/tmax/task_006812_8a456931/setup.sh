#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user/motif_analysis
    cd /home/user/motif_analysis

    # Generate a 10x10 transition matrix
    cat << 'EOF' > generate_matrix.py
import numpy as np
np.random.seed(42)
# Create a stochastic matrix
P = np.random.rand(10, 10)
# Make it have a specific structure that might cause standard solvers to complain if formulated badly
P[5, :] = 0
P[5, 5] = 1.0 # Absorbing state
P = P / P.sum(axis=1, keepdims=True)
np.savetxt("transition_matrix.csv", P, delimiter=",", fmt="%.6f")
EOF
    python3 generate_matrix.py
    rm generate_matrix.py

    # Buggy script
    cat << 'EOF' > solve_steady.py
import numpy as np

P = np.loadtxt("transition_matrix.csv", delimiter=",")
I = np.eye(10)
# This will fail because P.T - I is singular
A = P.T - I
b = np.zeros(10)

try:
    # Fails on singular input
    A_inv = np.linalg.inv(A)
    pi = A_inv @ b
    print("Steady state:", pi)
except np.linalg.LinAlgError as e:
    print(f"Failed to factorize matrix: {e}")
    exit(1)
EOF
    chmod +x solve_steady.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
