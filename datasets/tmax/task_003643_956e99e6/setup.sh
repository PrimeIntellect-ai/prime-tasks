#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
N = 50
A = np.random.rand(N, N)
A = (A + A.T) / 2
np.fill_diagonal(A, 0)
s = np.random.rand(N)

with h5py.File('/home/user/input.h5', 'w') as f:
    f.create_dataset('A', data=A)
    f.create_dataset('s', data=s)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
