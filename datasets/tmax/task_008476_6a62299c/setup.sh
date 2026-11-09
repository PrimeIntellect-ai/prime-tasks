#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import h5py
import numpy as np

# Deterministic generation
t = np.linspace(0, 2, 500)
h = 0.01 * (1 + 0.5 * np.sin(10 * t))
y_true = np.exp(-5 * t)
# Introduce a synthetic error profile that depends on h^2
y_num = y_true + 2.5 * h**2 * np.exp(-t)

with h5py.File('/home/user/simulation_data.h5', 'w') as f:
    f.create_dataset('time', data=t)
    f.create_dataset('step_size', data=h)
    f.create_dataset('y_numeric', data=y_num)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
