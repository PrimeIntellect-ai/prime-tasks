#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate initial data
    cat << 'EOF' > /tmp/gen_data.py
import h5py
import numpy as np

np.random.seed(42)
x = np.linspace(10, 15, 50)
# Underlying true model: c0=1.0, c1=-0.5, c2=0.1, c3=0.02
y = 1.0 - 0.5*x + 0.1*(x**2) + 0.02*(x**3) + np.random.normal(0, 0.5, 50)

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('x', data=x, dtype='float64')
    f.create_dataset('y', data=y, dtype='float64')
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Set permissions
    chmod -R 777 /home/user
