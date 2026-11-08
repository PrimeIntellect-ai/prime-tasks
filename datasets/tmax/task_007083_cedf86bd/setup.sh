#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest h5py matplotlib numpy
apt-get install -y libeigen3-dev g++

useradd -m -s /bin/bash user || true

python3 -c "
import h5py
import numpy as np

# Set fixed seed for reproducibility
np.random.seed(42)

# Generate design matrix X (50x4)
X = np.random.randn(50, 4)

# True beta
beta_true = np.array([1.5, -2.0, 0.5, 4.2])

# Generate observations y with some noise
y = X.dot(beta_true) + np.random.normal(0, 0.1, 50)

# Write to HDF5
with h5py.File('/home/user/experiment.h5', 'w') as f:
    f.create_dataset('/design_matrix', data=X)
    f.create_dataset('/observations', data=y)

# Calculate exact expected beta for verification
beta_hat, _, _, _ = np.linalg.lstsq(X, y, rcond=None)
with open('/home/user/.expected_beta.txt', 'w') as f:
    for b in beta_hat:
        f.write(f'{b:.4f}\n')

# Calculate exact residuals
residuals = y - X.dot(beta_hat)
with open('/home/user/.expected_residuals.txt', 'w') as f:
    for r in residuals:
        f.write(f'{r:.6f}\n')
"

chmod -R 777 /home/user
