#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_matrix.py
import numpy as np

# Create a highly correlated 5x5 matrix
np.random.seed(42)
base = np.random.randn(5, 4) # Rank 4
cov = np.dot(base, base.T)

# Save to CSV
np.savetxt('/home/user/cov_matrix.csv', cov, delimiter=',', fmt='%.8f')
EOF

    python3 /home/user/generate_matrix.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
