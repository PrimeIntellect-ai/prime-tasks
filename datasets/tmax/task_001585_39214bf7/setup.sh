#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np
np.random.seed(42)
X = np.random.rand(100, 10)
P = np.random.rand(10, 3)
Y = X @ P
np.savetxt('/home/user/X.txt', X, fmt='%.6f')
np.savetxt('/home/user/P.txt', P, fmt='%.6f')

# Add slight noise to Y_ref to make the diff non-zero but small
Y_ref = Y + np.random.normal(0, 1e-5, Y.shape)
np.savetxt('/home/user/Y_ref.txt', Y_ref, fmt='%.6f')
EOF

    python3 /home/user/setup.py

    chmod -R 777 /home/user
