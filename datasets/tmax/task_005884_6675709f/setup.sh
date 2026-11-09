#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/generate.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
n = 1000
A = np.random.normal(0, 1, n)
B = A * 3.14 + np.random.normal(0, 0.01, n) # Highly correlated with A
C = np.random.normal(5, 2, n)
D = np.random.normal(100, 15, n)

target = 2.0 * A - 1.5 * C + np.random.normal(0, 0.5, n)
missing_idx = np.random.choice(n, 50, replace=False)
target[missing_idx] = np.nan

df = pd.DataFrame({'sensor_A': A, 'sensor_B': B, 'sensor_C': C, 'sensor_D': D, 'target_temp': target})
df.to_csv('/home/user/data/sensors_raw.csv', index=False)
EOF

    python3 /home/user/data/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
