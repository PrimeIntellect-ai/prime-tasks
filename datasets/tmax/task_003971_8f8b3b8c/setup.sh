#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    mkdir -p /home/user/data
    mkdir -p /home/user/results

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py
import os

np.random.seed(0)
t = np.linspace(0, 1, 1000, endpoint=False)
signal = np.sin(2 * np.pi * 10 * t) + 0.5 * np.sin(2 * np.pi * 25 * t)
noise = np.random.normal(0, 0.2, 1000)
raw_signal = signal + noise

with h5py.File('/home/user/data/signal.h5', 'w') as f:
    f.create_dataset('raw_signal', data=raw_signal)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
