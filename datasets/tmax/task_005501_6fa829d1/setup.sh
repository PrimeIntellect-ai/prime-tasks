#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

np.random.seed(42)
base = np.random.randn(3, 50)
coeffs = np.random.randn(100, 3)
clean = coeffs @ base
noise = np.random.randn(100, 50) * 0.5
data = clean + noise

os.makedirs('/home/user', exist_ok=True)
np.savetxt('/home/user/spectra.csv', data, delimiter=',', fmt='%.6f')
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
