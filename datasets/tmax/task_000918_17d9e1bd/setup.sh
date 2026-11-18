#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np
import os

x = np.linspace(-10, 10, 1000)
# A mixture of two Gaussians as the raw signal
raw_signal = np.exp(-(x - 1.0)**2 / (2 * 1.5**2)) + 0.1 * np.exp(-(x + 2.0)**2 / (2 * 0.5**2))

with h5py.File('/home/user/sensor_data.h5', 'w') as f:
    f.create_dataset('x', data=x)
    f.create_dataset('raw_signal', data=raw_signal)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
