#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libhdf5-dev python3-h5py python3-numpy
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import h5py
import numpy as np

# Reproducible data generation
np.random.seed(42)
# True distribution is Gaussian with mean 5.0 and std 1.2
data = np.random.normal(loc=5.0, scale=1.2, size=10000).astype(np.float64)

with h5py.File('/home/user/sim_data.h5', 'w') as f:
    f.create_dataset('energies', data=data)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
