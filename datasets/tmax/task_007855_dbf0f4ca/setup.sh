#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py scipy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import h5py
import numpy as np

np.random.seed(42)
ref_a = np.random.rand(1000)
ref_b = np.random.rand(1000)
alpha_true = 0.65
target = alpha_true * ref_a + (1 - alpha_true) * ref_b + np.random.normal(0, 0.01, 1000)

with h5py.File('/home/user/data/profiles.h5', 'w') as f:
    f.create_dataset('reference_A', data=ref_a)
    f.create_dataset('reference_B', data=ref_b)
    f.create_dataset('target_sample', data=target)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
