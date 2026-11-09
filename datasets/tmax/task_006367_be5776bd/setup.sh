#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd
from sklearn.datasets import make_regression

os.makedirs('/home/user/data', exist_ok=True)

# Generate synthetic dataset
np.random.seed(123)
X, y = make_regression(n_samples=500, n_features=20, n_informative=5, noise=15.0, random_state=123)

# Introduce collinearity and noise to make PCA useful
X[:, 10] = X[:, 0] * 1.5 + np.random.normal(0, 1, 500)
X[:, 11] = X[:, 1] * 0.8 + np.random.normal(0, 1, 500)
X[:, 12] = X[:, 2] * 2.0 + np.random.normal(0, 1, 500)

df_features = pd.DataFrame(X, columns=[f'sensor_{i}' for i in range(20)])
df_features['sample_id'] = range(1000, 1500)

# Introduce missing values
mask = np.random.rand(*df_features.iloc[:, :20].shape) < 0.05
df_features.iloc[:, :20] = df_features.iloc[:, :20].mask(mask)

df_features = df_features[['sample_id'] + [f'sensor_{i}' for i in range(20)]]
df_features.to_csv('/home/user/data/sensor_features.csv', index=False)

df_targets = pd.DataFrame({'sample_id': range(1000, 1500), 'target': y})
# Shuffle targets to ensure they have to merge properly
df_targets = df_targets.sample(frac=1.0, random_state=123).reset_index(drop=True)
df_targets.to_csv('/home/user/data/sensor_targets.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
