#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_data.py
import csv
import numpy as np

np.random.seed(123)
M, N = 100, 20
# Create a rank 3 signal matrix
U = np.random.randn(M, 3)
S = np.diag([50.0, 30.0, 15.0])
V = np.random.randn(3, N)
Signal = U @ S @ V
# Add noise
Noise = np.random.randn(M, N) * 2.0
Data = Signal + Noise

with open('/home/user/sensor_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time_idx', 'sensor_idx', 'reading'])
    # Write in a shuffled order
    indices = [(i, j) for i in range(M) for j in range(N)]
    np.random.shuffle(indices)
    for i, j in indices:
        writer.writerow([i, j, Data[i, j]])
EOF

python3 /tmp/setup_data.py

export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
chmod -R 777 /usr/local/cargo /usr/local/rustup

chmod -R 777 /home/user
