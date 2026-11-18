#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)

# Generate Dataset 1: Actually Normal
np.random.seed(42)
d1 = np.random.normal(loc=5.0, scale=2.0, size=10000)
d1.astype(np.float64).tofile('/home/user/data/dataset_1.bin')

# Generate Dataset 2: Actually Laplace
np.random.seed(99)
d2 = np.random.laplace(loc=-3.0, scale=1.5, size=10000)
d2.astype(np.float64).tofile('/home/user/data/dataset_2.bin')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
