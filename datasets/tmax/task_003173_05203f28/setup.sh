#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

np.random.seed(42)
true_lambda = 3.14159
data = np.random.exponential(scale=1.0/true_lambda, size=1000000).astype(np.float64)

file_path = '/home/user/execution_times.bin'
data.tofile(file_path)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
