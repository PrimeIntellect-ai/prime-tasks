#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip hdf5-tools gawk bc
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

# Matrix A
A = np.array([
    [2, 3, 1],
    [4, 7, 5],
    [-2, 2, 6]
], dtype=np.float64)

# LU Decomposition
L = np.array([
    [1, 0, 0],
    [2, 1, 0],
    [-1, 5, 1]
], dtype=np.float64)

U = np.array([
    [2, 3, 1],
    [0, 1, 3],
    [0, 0, -8]
], dtype=np.float64)

with h5py.File('/home/user/matrix.h5', 'w') as f:
    f.create_dataset('/A', data=A)

with h5py.File('/home/user/ref.h5', 'w') as f:
    f.create_dataset('/L', data=L)
    f.create_dataset('/U', data=U)
EOF
    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
