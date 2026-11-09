#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import os

np.random.seed(42)

# Generate baseline data
B = np.random.normal(0, 1, (1000, 50))
np.savetxt('/home/user/baseline_data.csv', B, delimiter=',')

# Generate simulated data
t = np.arange(1000)
# Dominant freq = 25 cycles per 1000 samples -> index 25
signal1 = np.sin(2 * np.pi * 25 * t / 1000)[:, None] * np.random.normal(2, 0.5, 50)[None, :]
# Secondary freq = 100 cycles per 1000 samples -> index 100
signal2 = np.sin(2 * np.pi * 100 * t / 1000)[:, None] * np.random.normal(1, 0.2, 50)[None, :]

noise = np.random.normal(0, 0.5, (1000, 50))
A = signal1 + signal2 + noise
np.savetxt('/home/user/simulated_data.csv', A, delimiter=',')
EOF

python3 /tmp/setup_data.py
rm /tmp/setup_data.py

chmod -R 777 /home/user
