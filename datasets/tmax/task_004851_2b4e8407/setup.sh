#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

# Create deterministic data
np.random.seed(42)
X = np.random.randn(1000, 50)

# Add correlation so variance isn't uniformly distributed
cov = np.random.randn(50, 50)
cov = cov @ cov.T
L = np.linalg.cholesky(cov)
X = X @ L.T

np.save('/home/user/features.npy', X)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
