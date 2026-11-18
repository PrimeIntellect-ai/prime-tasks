#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_signal.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.linspace(400, 1000, 6000)

mu1, sig1, A1 = 500.0, 20.0, 0.5
mu2, sig2, A2 = 700.0, 30.0, 0.6

# Ideal signal
y = 1.0 - A1 * np.exp(-(x - mu1)**2 / (2 * sig1**2)) - A2 * np.exp(-(x - mu2)**2 / (2 * sig2**2))

# Add noise
y += np.random.normal(0, 0.005, size=len(x))

# Add divergence artifact for x > 800
diverge_mask = x > 800
y[diverge_mask] += (x[diverge_mask] - 800)**2 * np.sin(x[diverge_mask] * 10) * 0.01

df = pd.DataFrame({'wavelength': x, 'intensity': y})
df.to_csv('/home/user/raw_signal.csv', index=False)
EOF

    python3 /tmp/generate_signal.py
    rm /tmp/generate_signal.py

    chmod -R 777 /home/user
