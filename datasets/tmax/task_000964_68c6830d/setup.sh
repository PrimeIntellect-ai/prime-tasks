#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import h5py
import numpy as np

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
num_chains = 10
num_steps = 1000
num_dims = 2

data = np.random.normal(loc=0.0, scale=1.0, size=(num_chains, num_steps, num_dims))

# Make chains 2 and 5 diverge
data[2, 500:, 0] += np.linspace(0, 1e5, 500)
data[5, 800:, 1] -= np.linspace(0, 1e6, 200)

with h5py.File('/home/user/mcmc_samples.h5', 'w') as f:
    f.create_dataset('trajectories', data=data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
