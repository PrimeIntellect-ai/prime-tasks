#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)

# Generate base records
n_base = 800
n_features = 50
base_features = np.random.randn(n_base, n_features) * 2.0

# Create some artificial correlations to make PCA meaningful
transformation = np.random.randn(n_features, n_features)
base_features = np.dot(base_features, transformation)

# Create near duplicates
n_duplicates = 45
duplicate_indices = np.random.choice(n_base, n_duplicates, replace=False)
noise = np.random.randn(n_duplicates, n_features) * 0.05
dup_features = base_features[duplicate_indices] + noise

# Combine
all_features = np.vstack([base_features, dup_features])
ids = np.arange(100, 100 + len(all_features))

# Shuffle completely
shuffle_idx = np.random.permutation(len(all_features))
all_features = all_features[shuffle_idx]
ids = ids[shuffle_idx]

df = pd.DataFrame(all_features, columns=[f"v{i}" for i in range(n_features)])
df.insert(0, 'id', ids)

os.makedirs("/home/user/data", exist_ok=True)
df.to_csv("/home/user/data/embeddings.csv", index=False)
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
