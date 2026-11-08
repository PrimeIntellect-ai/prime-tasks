#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy

mkdir -p /home/user

python3 -c "
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

# Generate raw data
np.random.seed(123)
N = 100
data = np.random.randn(N, 50, 50)

# Corrupt some matrices to simulate numerical divergence
corrupted_indices = np.random.choice(N, 15, replace=False)

# Inject NaNs
for idx in corrupted_indices[:7]:
    data[idx, 10, 10] = np.nan
    data[idx, 40, 40] = np.nan

# Inject massive values
for idx in corrupted_indices[7:]:
    data[idx, 5, 5] = 2e6
    data[idx, 25, 25] = -3e6

np.save('/home/user/raw_data.npy', data)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
