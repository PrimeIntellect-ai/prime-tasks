#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn tables

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/raw_data', exist_ok=True)
np.random.seed(100)

for i in range(3):
    n_samples = 5000
    X = np.random.randn(n_samples, 10) * 5
    # Introduce some outliers in feature_0
    X[:50, 0] = 50.0 
    X[50:100, 0] = -50.0

    # Generate target
    true_coef = np.random.randn(10)
    y = X.dot(true_coef) + np.random.randn(n_samples) * 0.5

    # Introduce NaNs in target
    y[np.random.choice(n_samples, 200, replace=False)] = np.nan

    df = pd.DataFrame(X, columns=[f'feature_{j}' for j in range(10)])
    df['target'] = y

    df.to_csv(f'/home/user/raw_data/data_{i}.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
