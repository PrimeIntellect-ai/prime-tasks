#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
N = 100000

A = np.random.randn(N, 3).astype(np.float32)
B = np.random.randn(N, 2).astype(np.float32)

B[:, 0] += A[:, 0] * 0.5
B[:, 1] -= A[:, 2] * 0.8

A.tofile('/home/user/data_A.bin')
B.tofile('/home/user/data_B.bin')

C = np.concatenate([A, B], axis=1)
cov = np.cov(C, rowvar=False).astype(np.float32)
cov.tofile('/home/user/expected_cov_matrix.bin')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
