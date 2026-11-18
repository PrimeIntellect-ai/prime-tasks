#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py

def logistic(x, L, k, x0, b):
    return L / (1 + np.exp(-k * (x - x0))) + b

cycles = np.arange(1, 41)
num_samples = 20
fluorescence = np.zeros((num_samples, len(cycles)))

np.random.seed(42)
for i in range(num_samples):
    L = np.random.uniform(800, 1200)
    k = np.random.uniform(0.3, 0.8)
    x0 = np.random.uniform(15, 30)
    b = np.random.uniform(10, 50)

    # Force exact parameters for sample 15
    if i == 15:
        L, k, x0, b = 1000.0, 0.5, 22.5, 50.0

    y = logistic(cycles, L, k, x0, b)
    # Add minimal noise, except for sample 15 which gets 0 noise for exact validation
    if i != 15:
        y += np.random.normal(0, 2, len(cycles))

    fluorescence[i, :] = y

with h5py.File('/home/user/qpcr_data.h5', 'w') as f:
    f.create_dataset('cycles', data=cycles)
    f.create_dataset('fluorescence', data=fluorescence)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
