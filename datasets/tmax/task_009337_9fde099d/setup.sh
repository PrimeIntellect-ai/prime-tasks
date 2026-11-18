#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/matrix_prep

    cat << 'EOF' > /tmp/generate_matrices.py
import os
import numpy as np

os.makedirs("/home/user/data", exist_ok=True)
np.random.seed(42)

for i in range(10):
    if i % 3 == 0:
        # Well conditioned, positive definite
        A = np.random.randn(3, 3)
        A = A @ A.T + np.eye(3)
    elif i % 3 == 1:
        # Near singular
        A = np.random.randn(3, 3)
        A = A @ A.T
        w, v = np.linalg.eigh(A)
        w[0] = 1e-15 # very close to zero
        A = v @ np.diag(w) @ v.T
    else:
        # Not positive definite
        A = np.random.randn(3, 3)
        A = A + A.T
        w, v = np.linalg.eigh(A)
        w[0] = -1.0 # definitely not PD
        A = v @ np.diag(w) @ v.T

    np.savetxt(f"/home/user/data/matrix_{i}.csv", A, delimiter=",", fmt="%.8e")
EOF

    python3 /tmp/generate_matrices.py
    rm /tmp/generate_matrices.py

    chmod -R 777 /home/user
