#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user/experiments', exist_ok=True)
np.random.seed(42)

epochs = np.arange(1, 101)
base_loss = np.exp(-epochs/20.0) + np.random.normal(0, 0.05, 100)

with open('/home/user/experiments/baseline.csv', 'w') as f:
    f.write("epoch,loss\n")
    for e, l in zip(epochs, base_loss):
        f.write(f"{e},{l:.4f}\n")

cands = [
    base_loss + np.random.normal(0, 0.05, 100),
    base_loss[::-1],
    np.random.normal(0, 1, 100),
    base_loss * 0.5 + np.random.normal(0, 0.02, 100),
    np.log(epochs) / 5.0
]

for i, c_loss in enumerate(cands, 1):
    with open(f'/home/user/experiments/cand_{i}.csv', 'w') as f:
        f.write("epoch,loss\n")
        for e, l in zip(epochs, c_loss):
            f.write(f"{e},{l:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
