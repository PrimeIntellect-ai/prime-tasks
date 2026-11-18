#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/simulate.py
import numpy as np
import random

def simulate_v1(N, seed=42):
    random.seed(seed)
    results = []
    for _ in range(N):
        pos = sum(random.gauss(0, 1) for _ in range(100))
        results.append(pos)
    return np.array(results)

def simulate_v2(N, seed=42):
    np.random.seed(seed)
    # BUG: scale is 1.05 instead of 1.0
    steps = np.random.normal(loc=0.0, scale=1.05, size=(N, 100))
    return np.sum(steps, axis=1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
