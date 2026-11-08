#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 500

f1 = np.random.normal(0, 1, n_samples)
f2 = np.random.normal(5, 2, n_samples)
f3 = np.random.normal(-3, 1.5, n_samples)

target = 3.5 * f1 - 1.2 * f2 + 0.8 * f3 + np.random.normal(0, 0.5, n_samples)

# Add missing values to features
f1[np.random.choice(n_samples, 20, replace=False)] = np.nan
f2[np.random.choice(n_samples, 15, replace=False)] = np.nan
f3[np.random.choice(n_samples, 25, replace=False)] = np.nan

# Add massive outliers to target
outlier_indices = np.random.choice(n_samples, 10, replace=False)
target[outlier_indices] = target[outlier_indices] + np.random.choice([100, -100], 10)

df = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'target': target})
df.to_csv('/home/user/data/raw_data.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
