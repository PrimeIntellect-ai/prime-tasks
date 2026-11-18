#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import h5py
import numpy as np

x = np.linspace(0, 1, 50)
y = np.linspace(0, 1, 50)
z = np.linspace(0, 1, 50)
X, Y, Z = np.meshgrid(x, y, z, indexing='ij')

density = np.exp(-(X**2 + Y**2 + Z**2))

with h5py.File('/home/user/input_pdf.h5', 'w') as f:
    f.create_dataset('density', data=density)
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
