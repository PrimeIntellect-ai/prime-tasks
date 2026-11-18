#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate.py
import os
import math
import numpy as np

os.makedirs('/home/user/spectra_raw', exist_ok=True)

x = np.linspace(400, 800, 100)

# Ideal reference (Gaussian peak at 600)
def gaussian(x, mu, sig):
    return np.exp(-np.power(x - mu, 2.) / (2 * np.power(sig, 2.)))

y_ref = gaussian(x, 600, 20) + 0.1
with open('/home/user/reference_spectrum.csv', 'w') as f:
    for i in range(100):
        f.write(f"{x[i]:.2f},{y_ref[i]:.6f}\n")

# Generate samples
np.random.seed(42)
for i in range(1, 11):
    # Base signal with slight shifts
    mu = 600 + np.random.normal(0, 5)
    sig = 20 + np.random.normal(0, 2)
    y_base = gaussian(x, mu, sig)

    # Add random linear baseline
    m = np.random.uniform(-0.005, 0.005)
    c = np.random.uniform(0.5, 2.0)
    y_baseline = m * x + c

    # Add noise
    noise = np.random.normal(0, 0.02, 100)

    # Corrupt some samples heavily (KL div > 0.15)
    if i in [2, 5, 8]:
        y_base += gaussian(x, 500, 30) * 1.5 # spurious huge peak

    y_final = y_base + y_baseline + noise

    with open(f'/home/user/spectra_raw/sample_{i}.csv', 'w') as f:
        for j in range(100):
            f.write(f"{x[j]:.2f},{y_final[j]:.6f}\n")
EOF

    python3 /tmp/generate.py
    rm /tmp/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
