#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py scipy pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import h5py
import numpy as np

# Create spatial grid
x = np.arange(100.0)
y = np.arange(100.0)

# True model: T(x,y) = 0.5x - 0.2y + 15
X, Y = np.meshgrid(x, y, indexing='ij')
temperature = 0.5 * X - 0.2 * Y + 15.0

with h5py.File('/home/user/experiment_data.h5', 'w') as f:
    f.create_dataset('x', data=x)
    f.create_dataset('y', data=y)
    f.create_dataset('temperature', data=temperature)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
