#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs("/home/user", exist_ok=True)
np.random.seed(42)

# Generate a near-singular design matrix
X1 = np.random.randn(100)
X2 = np.random.randn(100)
# X3 is a linear combination of X1 and X2 plus tiny noise
X3 = X1 + X2 + np.random.randn(100) * 1e-4
X = np.column_stack((X1, X2, X3))

# True parameters
p_true = np.array([0.5, 1.2, 3.0])
y = X @ p_true

np.savetxt("/home/user/design_matrix.csv", X, delimiter=",")
np.savetxt("/home/user/target.csv", y, delimiter=",")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
