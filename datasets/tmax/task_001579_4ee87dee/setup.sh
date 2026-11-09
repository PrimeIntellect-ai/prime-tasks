#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libeigen3-dev
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
N = 100
ids = np.arange(1, N + 1)
f1 = np.random.randn(N) * 2 + 5
f2 = np.random.randn(N) * 3 - 2
# True beta = [1.5, -0.8]
y = 1.5 * f1 + (-0.8) * f2 + np.random.randn(N) * 0.5

# Introduce NaNs
f1[np.random.choice(N, 10, replace=False)] = np.nan
f2[np.random.choice(N, 15, replace=False)] = np.nan

df = pd.DataFrame({'id': ids, 'f1': f1, 'f2': f2, 'y': y})
df.to_csv('/home/user/dataset.csv', index=False, na_rep='NaN')

# Calculate ground truth to verify
df_clean = df.copy()
df_clean['f1'] = df_clean['f1'].fillna(df_clean['f1'].mean())
df_clean['f2'] = df_clean['f2'].fillna(df_clean['f2'].mean())

df_clean['f1'] = df_clean['f1'].apply(lambda x: f"{x:.4f}")
df_clean['f2'] = df_clean['f2'].apply(lambda x: f"{x:.4f}")
df_clean['y']  = df_clean['y'].apply(lambda x: f"{x:.4f}")
df_clean.to_csv('/home/user/expected_clean_data.csv', index=False)

# Compute expected best lambda
X = df_clean[['f1', 'f2']].astype(float).values
Y = df_clean['y'].astype(float).values

fold_size = 20
lambdas = [0.1, 1.0, 10.0]
best_l = None
best_mse = float('inf')

for l in lambdas:
    mse_total = 0
    for i in range(5):
        val_idx = list(range(i*fold_size, (i+1)*fold_size))
        train_idx = list(range(0, i*fold_size)) + list(range((i+1)*fold_size, 100))

        X_train, Y_train = X[train_idx], Y[train_idx]
        X_val, Y_val = X[val_idx], Y[val_idx]

        # beta = (X^T X + l*I)^-1 X^T Y
        I = np.eye(2)
        beta = np.linalg.inv(X_train.T @ X_train + l * I) @ X_train.T @ Y_train

        preds = X_val @ beta
        mse = np.mean((Y_val - preds)**2)
        mse_total += mse

    avg_mse = mse_total / 5
    if avg_mse < best_mse:
        best_mse = avg_mse
        best_l = l

with open('/home/user/expected_best_lambda.txt', 'w') as f:
    f.write(str(best_l))

EOF

    python3 /home/user/generate_data.py
    chmod -R 777 /home/user
