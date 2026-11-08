#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libhdf5-dev libgsl-dev python3-h5py python3-numpy gcc build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

# Set random seed for reproducibility
np.random.seed(42)

# Create a 100x50 matrix of random uniform values
matrix = np.random.rand(100, 50).astype(np.float64)

# Save to HDF5
with h5py.File('/home/user/sim_matrix.h5', 'w') as f:
    f.create_dataset('matrix_data', data=matrix, dtype='float64')

# Calculate SVD using numpy to get the true singular values
U, S, Vh = np.linalg.svd(matrix, full_matrices=False)

# Get the top 3 singular values
top_3_S = S[:3]

# Perturb them to create the reference data
# MAE will be (0.1 + 0.05 + 0.02) / 3 = 0.056666...
ref_S = top_3_S + np.array([0.1, -0.05, 0.02])

with open('/home/user/reference_sv.txt', 'w') as f:
    for val in ref_S:
        f.write(f"{val:.6f}\n")

# Calculate expected outputs to write to a secret file for validation if needed
with open('/tmp/expected_sv.txt', 'w') as f:
    for val in top_3_S:
        f.write(f"{val:.6f}\n")

EOF

python3 /tmp/setup_data.py
chown user:user /home/user/sim_matrix.h5 /home/user/reference_sv.txt

chmod -R 777 /home/user
