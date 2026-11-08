#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip hdf5-tools gcc
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_h5.py
import h5py
import numpy as np

# Transition matrix P where rows sum to 1
P = np.array([
    [0.2, 0.3, 0.1, 0.4],
    [0.1, 0.5, 0.2, 0.2],
    [0.4, 0.1, 0.3, 0.2],
    [0.3, 0.2, 0.4, 0.1]
])

with h5py.File('/home/user/transitions.h5', 'w') as f:
    f.create_dataset('matrix', data=P, dtype='float64')
EOF

    python3 /tmp/generate_h5.py
    chown user:user /home/user/transitions.h5

    chmod -R 777 /home/user
