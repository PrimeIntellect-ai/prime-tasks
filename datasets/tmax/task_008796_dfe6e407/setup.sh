#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
n_samples = 1000
n_features = 10

X = np.random.randn(n_samples, n_features)
X[:, 7] = 2.5 * X[:, 2] + 0.1

df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(n_features)])

df['target_reg'] = 3.0 * df['feature_0'] - 1.5 * df['feature_4'] + np.random.randn(n_samples) * 0.5
nan_indices = np.random.choice(n_samples, size=50, replace=False)
df.loc[nan_indices, 'target_reg'] = np.nan

logits = 1.0 * df['feature_1'] + 2.0 * df['feature_5'] - 1.0 * df['feature_2']
probs = 1 / (1 + np.exp(-logits))
df['failure'] = (np.random.rand(n_samples) < probs).astype(int)

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
