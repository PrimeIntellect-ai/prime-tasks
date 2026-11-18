#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go wget
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

np.random.seed(42)
fs = 200.0
t = np.arange(0, 50, 1/fs) # 10000 points
# Dominant frequency at 15.4 Hz, secondary at 42.1 Hz
y = 3.0 * np.sin(2 * np.pi * 15.4 * t) + 1.5 * np.cos(2 * np.pi * 42.1 * t) + np.random.normal(0, 2.0, len(t))

with open("/home/user/data.csv", "w") as f:
    for i in range(len(t)):
        f.write(f"{t[i]},{y[i]}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
