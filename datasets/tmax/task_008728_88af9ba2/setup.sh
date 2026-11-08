#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-h5py python3-numpy libhdf5-dev libeigen3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import h5py
import numpy as np

np.random.seed(42)

# Create 5 matrices
matrices = np.zeros((5, 3, 3))

# 0: Strongly SPD
A0 = np.random.randn(3, 3)
matrices[0] = A0 @ A0.T + np.eye(3)

# 1: Singular (Rank 2)
A1 = np.random.randn(3, 2)
matrices[1] = A1 @ A1.T

# 2: Negative Definite (invalid covariance)
A2 = np.random.randn(3, 3)
matrices[2] = A2 @ A2.T
matrices[2][0,0] = -0.01

# 3: Strongly SPD
A3 = np.random.randn(3, 3)
matrices[3] = A3 @ A3.T + np.eye(3)

# 4: Near singular (has a small negative eigenvalue)
A4 = np.random.randn(3, 3)
m4 = A4 @ A4.T
w, v = np.linalg.eigh(m4)
w[0] = -1e-5
matrices[4] = v @ np.diag(w) @ v.T

with h5py.File('/home/user/covariances.h5', 'w') as f:
    f.create_dataset('cov_matrices', data=matrices, dtype='f8')
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
