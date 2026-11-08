#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np
np.random.seed(42)

# Generate 50 rows, 10 columns
data = np.random.randn(50, 10)

# Make col 3 highly correlated with col 0
data[:, 3] = data[:, 0] * 2.0 + np.random.randn(50) * 0.1

# Make col 7 highly negatively correlated with col 2
data[:, 7] = data[:, 2] * -1.5 + np.random.randn(50) * 0.1

np.savetxt('/home/user/data/embeddings.csv', data, delimiter=',', fmt='%.6f')
EOF
    python3 /home/user/data/generate_data.py

    chmod -R 777 /home/user
