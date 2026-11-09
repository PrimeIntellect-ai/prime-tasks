#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 << 'EOF'
import pandas as pd
import numpy as np
import json

# Generate data
np.random.seed(42)
X1 = np.random.normal(5, 2, 100)
X2 = 0.5 * X1 + np.random.normal(0, 1, 100)
y = 2.0 * X1 - 1.5 * X2 + np.random.normal(0, 0.5, 100)

df = pd.DataFrame({'X1': X1, 'X2': X2, 'y': y})
df.to_csv('/home/user/data.csv', index=False)

# Buggy script
buggy_code = """import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler

# Load data
df = pd.read_csv('/home/user/data.csv')
X = df[['X1', 'X2']].values
y = df['y'].values

# BUG: Data leakage!
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test = X_scaled[:80], X_scaled[80:]
y_train, y_test = y[:80], y[80:]

# Bayesian Linear Regression (known noise variance = 0.25, prior variance = 1.0)
sigma_noise_sq = 0.25
alpha = 1.0

# Posterior covariance: V_N = (1/alpha * I + 1/sigma_noise_sq * X^T X)^{-1}
I = np.eye(X_train.shape[1])
V_N = np.linalg.inv(I / alpha + (X_train.T @ X_train) / sigma_noise_sq)

# Posterior mean: w_N = V_N @ (1/sigma_noise_sq * X^T y)
w_N = V_N @ (X_train.T @ y_train) / sigma_noise_sq

# Predictions
y_pred = X_test @ w_N
print(f"Predictions: {y_pred}")
"""
with open('/home/user/bayesian_model.py', 'w') as f:
    f.write(buggy_code)
EOF

    chmod -R 777 /home/user
