#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libhdf5-dev g++ make gawk
    pip3 install pytest h5py numpy

    mkdir -p /home/user/data /home/user/src /home/user/bin /home/user/results

    cat << 'EOF' > /tmp/create_h5.py
import h5py
import numpy as np
np.random.seed(42)
data = np.random.uniform(0.0, 100.0, 1000000).astype(np.float64)
with h5py.File('/home/user/data/particles.h5', 'w') as f:
    f.create_dataset('/x_coords', data=data)
EOF
    python3 /tmp/create_h5.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
