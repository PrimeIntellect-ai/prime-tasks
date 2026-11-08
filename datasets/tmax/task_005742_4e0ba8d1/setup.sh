#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_task.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_regression

# Create reproducible synthetic data
X, y = make_regression(n_samples=1000, n_features=20, noise=0.5, random_state=42)
df = pd.DataFrame(X, columns=[f'feat_{i}' for i in range(20)])
df['target'] = y
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /home/user/setup_task.py

    cat << 'EOF' > /home/user/evaluate_model.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

# Load data
df = pd.read_csv('/home/user/data.csv')
X = df.drop('target', axis=1)
y = df['target']

# DATA LEAKAGE: Scaling before splitting
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = Ridge(alpha=1.0, random_state=42)
model.fit(X_train, y_train)
y_pred = model.predict(X_test)

print(f"Leaky Test MSE: {mean_squared_error(y_test, y_pred):.4f}")
EOF

    chmod -R 777 /home/user
