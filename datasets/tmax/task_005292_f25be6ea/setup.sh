#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

np.random.seed(42)
t = np.linspace(0, 5, 200)
# Create a degree 12 polynomial
coeffs_true = np.random.uniform(-1, 1, 13)
signal = np.polyval(coeffs_true, t)

with h5py.File('/home/user/signal.h5', 'w') as f:
    f.create_dataset('t', data=t)
    f.create_dataset('signal', data=signal)
EOF
    python3 /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
