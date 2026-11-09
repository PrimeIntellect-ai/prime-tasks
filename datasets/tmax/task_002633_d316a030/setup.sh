#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip hdf5-tools
    pip3 install pytest h5py numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import h5py
import numpy as np

with h5py.File('/home/user/data/seq_stats.h5', 'w') as f:
    f.create_dataset('Position', data=np.array([10, 20, 30, 40, 50], dtype=int))
    f.create_dataset('GC_content', data=np.array([40.0, 45.0, 50.0, 55.0, 60.0], dtype=float))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    echo "Slope: 0.50" > /home/user/data/baseline.txt
    echo "Intercept: 35.00" >> /home/user/data/baseline.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
