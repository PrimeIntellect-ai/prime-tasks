#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils curl
    pip3 install pytest pyinstaller h5py numpy flask requests scipy

    mkdir -p /app
    cat << 'EOF' > /app/build_sim.py
import sys
import h5py
import numpy as np

if len(sys.argv) != 2:
    sys.exit(1)

N = int(sys.argv[1])
np.random.seed() # Non-deterministic

i = np.arange(N).reshape(N, 1)
j = np.arange(N).reshape(1, N)
# Base signal
matrix = np.sin(i * j * 0.01)
# FP reduction order "noise"
noise = np.random.normal(0, 1e-5, (N, N))
matrix += noise

with h5py.File('sim_output.h5', 'w') as f:
    f.create_dataset('/covariance_matrix', data=matrix, dtype='float64')
EOF

    cd /app
    pyinstaller --onefile build_sim.py
    mv dist/build_sim /app/sim_binary
    strip /app/sim_binary
    rm -rf build_sim.py dist build build_sim.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
