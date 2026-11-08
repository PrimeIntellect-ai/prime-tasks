#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
N = 1000
M = 2048

data = np.random.randn(N, M).astype(np.float64)
for i in range(N):
    freq = 10 + (i % 50)
    t = np.arange(M)
    data[i] += np.sin(2 * np.pi * freq * t / M)

with open('/home/user/spectra.dat', 'wb') as f:
    f.write(data.tobytes())
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
