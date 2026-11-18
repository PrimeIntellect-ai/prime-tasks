#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np
import os

os.makedirs('/home/user/datasets', exist_ok=True)
np.random.seed(42)

# Generate target vector
target = np.random.randn(50)
np.savetxt('/home/user/target.csv', target, delimiter=',')

# Generate datasets
for i in range(10):
    data = np.random.randn(100, 50)
    data += np.random.randn(50) * 0.5 # Add random shift to mean
    np.savetxt(f'/home/user/datasets/dataset_{i}.csv', data, delimiter=',')

# Create fast_cov.py
fast_cov_code = \"\"\"import numpy as np

def compute_fast_cov(X):
    # Computes population covariance (ddof=0)
    # Numpy cov defaults to sample covariance (ddof=1)
    N = X.shape[0]
    X_centered = X - np.mean(X, axis=0)
    return (X_centered.T @ X_centered) / N
\"\"\"
with open('/home/user/fast_cov.py', 'w') as f:
    f.write(fast_cov_code)
"

    chmod -R 777 /home/user
