#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create initial state
    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
A = np.random.randn(100, 10)
# Make columns 0 and 1 highly collinear to simulate near-singularity
A[:, 1] = A[:, 0] + 1e-6 * np.random.randn(100)
true_x = np.random.randn(10)
b = A @ true_x + 0.1 * np.random.randn(100)

with h5py.File('/home/user/input.h5', 'w') as f:
    f.create_dataset('A', data=A)
    f.create_dataset('b', data=b)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
