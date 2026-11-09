#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy cargo curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    python3 -c '
import struct
import numpy as np

# Generate 1,000,000 points
np.random.seed(42)
N = 1000000
Y = np.random.normal(0, 0.1, N).astype(np.float32)

# Insert a strong Gaussian peak
k_center = 500000
true_alpha = 4.25
j_vals = np.arange(-500, 500)
Y[k_center - 500 : k_center + 500] += 15.0 * np.exp(-(j_vals**2) / (true_alpha**2))

# Write to binary file
with open("/home/user/data/signal.bin", "wb") as f:
    f.write(Y.tobytes())
'

    chmod -R 777 /home/user
