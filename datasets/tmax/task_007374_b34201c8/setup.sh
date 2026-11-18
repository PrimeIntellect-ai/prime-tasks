#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

# Generate train
train_v1 = np.random.normal(5, 2, 100)
train_v2 = train_v1 * 0.5 + np.random.normal(0, 1, 100)

# Generate test
test_v1 = np.random.normal(8, 3, 50)
test_v2 = test_v1 * -0.2 + np.random.normal(0, 2, 50)

df = pd.DataFrame({
    'id': range(150),
    'split': ['train']*100 + ['test']*50,
    'v1': np.concatenate([train_v1, test_v1]),
    'v2': np.concatenate([train_v2, test_v2])
})
df.to_csv('/home/user/embeddings.csv', index=False)

# Compute ground truth
# LEAKY
mu_all_v1 = df['v1'].mean()
std_all_v1 = df['v1'].std(ddof=0)
mu_all_v2 = df['v2'].mean()
std_all_v2 = df['v2'].std(ddof=0)

test_df = df[df['split'] == 'test'].copy()
test_df['v1_leaky'] = (test_df['v1'] - mu_all_v1) / std_all_v1
test_df['v2_leaky'] = (test_df['v2'] - mu_all_v2) / std_all_v2
leaky_metric = (test_df['v1_leaky'] * test_df['v2_leaky']).mean()

# STRICT
train_df = df[df['split'] == 'train']
mu_train_v1 = train_df['v1'].mean()
std_train_v1 = train_df['v1'].std(ddof=0)
mu_train_v2 = train_df['v2'].mean()
std_train_v2 = train_df['v2'].std(ddof=0)

test_df['v1_strict'] = (test_df['v1'] - mu_train_v1) / std_train_v1
test_df['v2_strict'] = (test_df['v2'] - mu_train_v2) / std_train_v2
strict_metric = (test_df['v1_strict'] * test_df['v2_strict']).mean()

with open('/home/user/.expected_output', 'w') as f:
    f.write(f"LEAKY: {leaky_metric:.4f}\n")
    f.write(f"STRICT: {strict_metric:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
