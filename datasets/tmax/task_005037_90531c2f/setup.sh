#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

# Generate synthetic spatial data
np.random.seed(42)
x = np.linspace(0, 20, 60)
# Ground truth parameters
true_A = 4.5
true_mu = 8.2
true_sigma = 1.5
true_C = 1.0

# Exact data (no noise to guarantee consistent curve fitting to 4 decimals)
y = true_A * np.exp(-((x - true_mu)**2) / (2 * true_sigma**2)) + true_C

df = pd.DataFrame({'x': x, 'y': y})
df.to_csv('/home/user/spatial_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
