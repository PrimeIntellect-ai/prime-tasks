#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest h5py

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import h5py
import random

os.makedirs('/home/user/data', exist_ok=True)

# Generate a fixed sequence for reproducibility
random.seed(42)
bases = ['A', 'C', 'G', 'T']
seq = ''.join(random.choices(bases, k=1000))

with h5py.File('/home/user/data/reference.h5', 'w') as f:
    f.create_dataset('sequence', data=seq.encode('utf-8'))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
