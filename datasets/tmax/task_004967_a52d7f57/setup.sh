#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

np.random.seed(42)
# Create a rank-deficient covariance matrix (50x50, rank 40)
A = np.random.randn(50, 40)
cov = A @ A.T
np.save('/home/user/kmer_cov.npy', cov)

# Create sequence differences
diffs = np.random.randn(1000, 50)
np.save('/home/user/kmer_diffs.npy', diffs)
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
