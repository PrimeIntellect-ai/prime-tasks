#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy h5py

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import h5py
import os

os.makedirs("/home/user", exist_ok=True)

# Generate deterministic mock simulation data
rng = np.random.RandomState(42)
T, X = 200, 1000

# Create a low-rank signal + noise
t = np.linspace(0, 10, T)
x = np.linspace(0, 5, X)
T_mat, X_mat = np.meshgrid(t, x, indexing='ij')

# 3 dominant modes
signal = (
    np.sin(T_mat) * np.cos(X_mat) * 10.0 +
    np.cos(2*T_mat) * np.sin(2*X_mat) * 5.0 +
    np.sin(0.5*T_mat) * np.exp(-X_mat/2) * 2.0
)
noise = rng.randn(T, X) * 0.5
data = signal + noise

with h5py.File("/home/user/sim_data.h5", "w") as f:
    f.create_dataset("velocity_field", data=data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
