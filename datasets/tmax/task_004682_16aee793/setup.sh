#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev libfftw3-dev
    pip3 install pytest numpy h5py matplotlib

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import h5py
import numpy as np

np.random.seed(42)
signals = np.random.randn(1000, 1024).astype(np.float32)

t = np.arange(1024)
signals += 2.0 * np.sin(2 * np.pi * 50 * t / 1024).astype(np.float32)

with h5py.File('/home/user/data/signals.h5', 'w') as f:
    f.create_dataset('signals', data=signals)
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
