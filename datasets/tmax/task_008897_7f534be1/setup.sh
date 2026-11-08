#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

np.random.seed(42)

# Generate synthetic data
X = np.random.randn(100, 10)
# Generate a random projection matrix (10x3)
W = np.random.randn(10, 3)

np.savetxt('/home/user/data.csv', X, delimiter=',')
np.savetxt('/home/user/weights.csv', W, delimiter=',')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
