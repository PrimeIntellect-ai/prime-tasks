#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-h5py
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import h5py

np.random.seed(100)
X = np.random.randn(500, 30)

# Create deliberate collinearity to make rank exactly 26
for i in range(26, 30):
    X[:, i] = X[:, i-26] * 1.5 - X[:, i-25] * 0.8

beta_true = np.random.randn(30)
# Force the first three coefficients to ensure real roots in the approximate solution
beta_true[0] = 2.0
beta_true[1] = 8.0
beta_true[2] = -3.0

y = X @ beta_true + np.random.randn(500) * 0.5

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('X', data=X)
    f.create_dataset('y', data=y)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
