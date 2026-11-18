#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_mesh.py
import numpy as np
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)
grid = np.zeros((100, 100))
grid[0:50, 0:50] = np.random.normal(10.0, 2.0, (50, 50))  # Q1
grid[0:50, 50:100] = np.random.normal(10.0, 2.0, (50, 50)) # Q2
grid[50:100, 0:50] = np.random.normal(10.0, 2.0, (50, 50)) # Q3
grid[50:100, 50:100] = np.random.normal(10.5, 2.5, (50, 50)) # Q4

np.savetxt('/home/user/data/mesh.csv', grid, delimiter=',')
EOF

    python3 /tmp/generate_mesh.py
    rm /tmp/generate_mesh.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
