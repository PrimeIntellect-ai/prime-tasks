#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

np.random.seed(42)
# Generate 100 random 50x50 matrices
matrices = np.random.randn(100, 50, 50)

# Make specific matrices near-singular to ensure cond >= 1e12
target_indices = [14, 27, 55, 89]
for i in target_indices:
    u, s, vh = np.linalg.svd(matrices[i])
    s[-1] = s[0] * 1e-13 # Force condition number to be ~1e13
    matrices[i] = u @ np.diag(s) @ vh

with h5py.File('/home/user/input_data.h5', 'w') as f:
    f.create_dataset('matrices', data=matrices)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
