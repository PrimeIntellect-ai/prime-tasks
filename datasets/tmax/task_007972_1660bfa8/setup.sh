#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

# Create deterministic stochastic data
np.random.seed(42)
# Use a gamma distribution so it's asymmetric and the mode isn't just the mean
data = np.random.gamma(shape=3.0, scale=2.0, size=10000)

with h5py.File('/home/user/sim_data.h5', 'w') as f:
    f.create_dataset('energies', data=data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
