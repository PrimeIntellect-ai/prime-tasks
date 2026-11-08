#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y libhdf5-dev g++ make python3-h5py python3-numpy jq wget tar

    # Install Eigen3 manually since libeigen-dev is not a valid package in 22.04 (it's usually libeigen3-dev, but downloading is safer)
    wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
    tar -xzf eigen-3.4.0.tar.gz
    cp -r eigen-3.4.0/Eigen /usr/local/include/
    cp -r eigen-3.4.0/Eigen /usr/include/
    rm -rf eigen-3.4.0.tar.gz eigen-3.4.0

    useradd -m -s /bin/bash user || true

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np

N = 100
M = 500
dt = 0.01

np.random.seed(42)
t = np.arange(M) * dt
A = np.zeros((N, M))
for i in range(N):
    freq = np.random.uniform(0.5, 2.0)
    A[i, :] = np.sin(2 * np.pi * freq * t) + 0.1 * np.random.randn(M)

with h5py.File('/home/user/input_data.h5', 'w') as f:
    f.create_dataset('/raw_signals', data=A, dtype='float64')

D = np.zeros_like(A)
D[:, 1:-1] = (A[:, 2:] - A[:, :-2]) / (2 * dt)
D[:, 0] = (A[:, 1] - A[:, 0]) / dt
D[:, -1] = (A[:, -1] - A[:, -2]) / dt

U, S, Vt = np.linalg.svd(D, full_matrices=False)
S_filtered = np.zeros_like(S)
S_filtered[:5] = S[:5]
D_filtered = U @ np.diag(S_filtered) @ Vt

I = np.trapz(D_filtered, dx=dt, axis=1)

np.savetxt('/home/user/reference.csv', I, delimiter=',')
EOF

    python3 /tmp/generate_data.py
    chown user:user /home/user/input_data.h5 /home/user/reference.csv
    chmod -R 777 /home/user
