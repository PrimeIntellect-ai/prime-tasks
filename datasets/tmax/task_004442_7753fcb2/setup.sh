#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(123)
n_rows = 5000

user_ids = np.arange(1000, 1000 + n_rows)
feature_x = np.random.uniform(10, 100, n_rows)
feature_y = np.random.uniform(1, 20, n_rows)
# Introduce zeros in feature_y
zero_indices = np.random.choice(n_rows, 50, replace=False)
feature_y[zero_indices] = 0.0

# Create target correlated with x/y
ratio_true = feature_x / feature_y
# handle infs for target generation
ratio_true[np.isinf(ratio_true)] = 0 
target = 2.5 * ratio_true + np.random.normal(0, 5, n_rows)

df = pd.DataFrame({
    'user_id': user_ids,
    'feature_x': np.round(feature_x, 2),
    'feature_y': np.round(feature_y, 2),
    'target': np.round(target, 2)
})

# Introduce missing user_ids (empty strings)
missing_uid_indices = np.random.choice(n_rows, 200, replace=False)
df.loc[missing_uid_indices, 'user_id'] = ""

df.to_csv('/home/user/metrics.csv', index=False)

# Ground truth calculation
df_clean = df[df['user_id'] != ""].copy()
df_clean['feature_y'] = df_clean['feature_y'].astype(float)
df_clean = df_clean[df_clean['feature_y'] != 0.0].copy()
df_clean['ratio'] = df_clean['feature_x'] / df_clean['feature_y']

df_sample = df_clean.sample(n=2000, replace=True, random_state=42)
corr = df_sample['ratio'].corr(df_sample['target'])

with open('/home/user/.expected_output', 'w') as f:
    f.write(f"{corr:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
