#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np

np.random.seed(42)
N = 2000
w_true = 0.35
mu1_true = 4.0
mu2_true = 11.0

# Generate data
n1 = int(N * w_true)
n2 = N - n1
data1 = np.random.normal(mu1_true, 1.0, n1)
data2 = np.random.normal(mu2_true, 1.0, n2)
data = np.concatenate([data1, data2])
np.random.shuffle(data)

with open("/home/user/latencies.txt", "w") as f:
    for val in data:
        f.write(f"{val:.6f}\n")
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
