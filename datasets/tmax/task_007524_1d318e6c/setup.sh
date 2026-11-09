#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_signal.py
import h5py
import numpy as np

# N = 1024, dt = 1/1024
t = np.linspace(0, 1, 1024, endpoint=False)

voltage = 1.0 * np.sin(2 * np.pi * 5 * t) + 0.6 * np.sin(2 * np.pi * 12 * t)

with h5py.File('/home/user/signal.h5', 'w') as f:
    f.create_dataset('/voltage', data=voltage, dtype='float64')
EOF

    python3 /tmp/generate_signal.py
    rm /tmp/generate_signal.py

    chmod -R 777 /home/user
