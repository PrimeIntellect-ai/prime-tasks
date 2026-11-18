#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import struct
import numpy as np

# Set random seed for reproducibility
np.random.seed(42)

# Generate 1000 records
N = 1000
cov_true = [[2.0, 0.5, -0.3], 
            [0.5, 1.5, 0.8], 
            [-0.3, 0.8, 2.5]]
mean_true = [10.0, -5.0, 2.0]

data = np.random.multivariate_normal(mean_true, cov_true, N).astype(np.float32)

# Introduce -999.0f in about 10% of the rows
corruption_indices = np.random.choice(N, size=100, replace=False)
for idx in corruption_indices:
    col = np.random.randint(0, 3)
    data[idx, col] = -999.0

# Write to binary file
with open('/home/user/raw_data.bin', 'wb') as f:
    f.write(data.tobytes())

# Compute ground truth to verify
valid_mask = ~np.any(data == -999.0, axis=1)
valid_data = data[valid_mask]

cov_matrix = np.cov(valid_data, rowvar=False, ddof=1)

with open('/home/user/ground_truth.txt', 'w') as f:
    for row in cov_matrix:
        f.write(f"{row[0]:.4f}, {row[1]:.4f}, {row[2]:.4f}\n")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
