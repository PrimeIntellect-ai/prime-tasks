#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

np.random.seed(123)
n_samples = 500

sensor_ids = [f'sensor_{i}' for i in range(n_samples)]
f1 = np.random.normal(10, 2, n_samples)
f2 = np.random.normal(50, 10, n_samples)
f3 = np.random.exponential(5, n_samples)
f4 = np.random.uniform(0, 100, n_samples)

target_f = 2.5 * f1 - 0.5 * f2 + 1.2 * f3 + np.random.normal(0, 5, n_samples)

missing_indices = np.random.choice(n_samples, size=int(0.2 * n_samples), replace=False)
if 0 in missing_indices:
    missing_indices = missing_indices[missing_indices != 0]

target_f[missing_indices] = np.nan

df = pd.DataFrame({
    'sensor_id': sensor_ids,
    'f1': f1,
    'f2': f2,
    'f3': f3,
    'f4': f4,
    'target_f': target_f
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
