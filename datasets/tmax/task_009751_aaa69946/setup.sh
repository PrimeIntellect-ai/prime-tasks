#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/spectra

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import os

os.makedirs('/home/user/spectra', exist_ok=True)
np.random.seed(42)

for i in range(100):
    # Create uneven observational grid
    x = np.sort(np.random.uniform(400, 800, 300))

    # Underlying ground truth parameters
    A_true = np.random.uniform(5, 15)
    mu_true = np.random.uniform(500, 700)
    sigma_true = np.random.uniform(10, 30)

    # Generate signal with Gaussian noise
    y = A_true * np.exp(-(x - mu_true)**2 / (2 * sigma_true**2))
    y += np.random.normal(0, 0.5, size=x.shape)

    # Save to file
    with open(f'/home/user/spectra/spec_{i:03d}.txt', 'w') as f:
        for xx, yy in zip(x, y):
            f.write(f"{xx:.4f},{yy:.4f}\n")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
