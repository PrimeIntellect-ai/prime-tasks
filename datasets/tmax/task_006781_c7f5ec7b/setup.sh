#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import struct
import os

np.random.seed(42)
N = 10000
M = 10

# Generate random data
data = np.random.randn(N, M)

# Create correlations
# Feature 0 and 3 are highly positively correlated
data[:, 3] = data[:, 0] * 2.0 + np.random.randn(N) * 0.1

# Feature 2 and 7 are highly negatively correlated
data[:, 7] = data[:, 2] * -1.5 + np.random.randn(N) * 0.2

# Write to binary file
file_path = '/home/user/dataset.bin'
with open(file_path, 'wb') as f:
    f.write(data.astype(np.float64).tobytes())

os.chmod(file_path, 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
