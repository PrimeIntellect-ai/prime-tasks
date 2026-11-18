#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy pandas scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 1000

# Generate normal features
mean = [0, 1, 2, 3, 4]
cov = [
    [1.0, 0.5, 0.2, 0.1, 0.0],
    [0.5, 2.0, 0.4, 0.2, 0.1],
    [0.2, 0.4, 3.0, 0.6, 0.2],
    [0.1, 0.2, 0.6, 4.0, 0.8],
    [0.0, 0.1, 0.2, 0.8, 5.0]
]
X = np.random.multivariate_normal(mean, cov, n_samples)
true_weights = np.array([1.5, -2.0, 0.5, 1.0, -0.5])
y = X.dot(true_weights) + np.random.normal(0, 1, n_samples)

# Add extreme outliers
n_outliers = 30
outlier_indices = np.random.choice(n_samples, n_outliers, replace=False)
X[outlier_indices] = X[outlier_indices] + np.random.normal(10, 5, size=(n_outliers, 5))
y[outlier_indices] = y[outlier_indices] + np.random.normal(50, 20, size=n_outliers)

df = pd.DataFrame(X, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
df['y'] = y
df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
