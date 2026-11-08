#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar sed
    pip3 install pytest numpy pandas scipy jupyter notebook

    mkdir -p /app
    cd /app
    wget https://github.com/lmfit/lmfit-py/archive/refs/tags/1.2.2.tar.gz
    tar -xzf 1.2.2.tar.gz
    mv lmfit-py-1.2.2 lmfit-1.2.2
    rm 1.2.2.tar.gz
    # Apply perturbation
    sed -i 's/numpy>=.*/numpy==1.9.0/' /app/lmfit-1.2.2/setup.cfg

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.linspace(0, 100, 500)
# True parameters for 3 peaks
p1 = 10.0 * np.exp(-(x - 20)**2 / (2 * 3**2))
p2 = 15.0 * np.exp(-(x - 50)**2 / (2 * 5**2))
p3 = 8.0 * np.exp(-(x - 75)**2 / (2 * 2**2))
baseline = 2.0
y_true = p1 + p2 + p3 + baseline

# Add noise
noise = np.random.normal(0, 0.5, size=x.shape)
y_noisy = y_true + noise

df = pd.DataFrame({'wavelength': x, 'intensity': y_noisy})
df.to_csv('/home/user/data/spectra.csv', index=False)

# Save ground truth normalized distribution for verifier
y_true_norm = y_true / np.sum(y_true)
np.save('/home/user/data/truth_norm.npy', y_true_norm)
EOF

    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
