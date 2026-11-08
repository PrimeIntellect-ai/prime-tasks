#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/profiling_data

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import os

np.random.seed(42)
os.makedirs("/home/user/profiling_data", exist_ok=True)

# P = 0.8, T(1) = 100
# Means: N=1: 100, N=2: 60, N=4: 40, N=8: 30
scales = {1: (100, 5), 2: (60, 3), 4: (40, 2), 8: (30, 1.5)}

for n, (mean, std) in scales.items():
    data = np.random.normal(loc=mean, scale=std, size=1000)
    np.savetxt(f"/home/user/profiling_data/rank_{n}.csv", data, fmt="%.4f", header="latency", comments="")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
