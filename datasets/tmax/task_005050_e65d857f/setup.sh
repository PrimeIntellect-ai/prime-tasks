#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np

np.random.seed(123)
X = np.random.randn(100, 10)
w_true = np.array([1.2, 0.2, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
y = X @ w_true + np.random.randn(100) * 0.5

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('X', data=X)
    f.create_dataset('y', data=y)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
