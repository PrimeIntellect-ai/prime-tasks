#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev
    pip3 install pytest numpy h5py scipy mpi4py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py

np.random.seed(42)
N = 200
M = 1000
X = np.random.normal(loc=1.0, scale=0.5, size=(N, M))

with h5py.File('/home/user/seq_data.h5', 'w') as f:
    f.create_dataset('embeddings', data=X, dtype='float64')
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
