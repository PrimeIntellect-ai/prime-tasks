#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

np.random.seed(42)
X = np.random.rand(100, 3) * 10
y = 2 * X[:, 0] + 0.5 * X[:, 1] - X[:, 2] + np.random.randn(100) * 0.5
data = np.column_stack((X, y))

with open('/home/user/data.csv', 'w') as f:
    for row in data:
        f.write(','.join(f"{val:.4f}" for val in row) + '\n')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
