#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import h5py
import numpy as np
import os

np.random.seed(42)

filename = '/home/user/profiling_data.h5'
with h5py.File(filename, 'w') as f:
    g1 = f.create_group('v1_slow')
    g2 = f.create_group('v2_fast')

    for i in range(50):
        data1 = np.random.normal(loc=0.0, scale=1.5, size=5000)
        g1.create_dataset(f'run_{i}', data=data1)

        data2 = np.random.normal(loc=0.0, scale=1.5 + np.random.uniform(-0.01, 0.01), size=5000)
        g2.create_dataset(f'run_{i}', data=data2)

os.chmod(filename, 0o644)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
