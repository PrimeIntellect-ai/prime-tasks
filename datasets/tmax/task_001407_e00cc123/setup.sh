#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libhdf5-dev
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/create_input.py
import h5py
import numpy as np

# Create a near-singular 10x10 matrix
np.random.seed(0)
A = np.random.rand(10, 5)
cov = np.dot(A, A.T) # Rank 5, size 10x10, so singular

with h5py.File('/home/user/data/input.h5', 'w') as f:
    f.create_dataset('cov_matrix', data=cov, dtype='float64')
EOF

    python3 /tmp/create_input.py
    rm /tmp/create_input.py

    chmod -R 777 /home/user
