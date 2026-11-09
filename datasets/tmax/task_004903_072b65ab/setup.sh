#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scikit-learn scipy numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=500, n_features=100, n_informative=20, random_state=42)
rng = np.random.RandomState(42)
mask = rng.rand(*X.shape) < 0.1
X[mask] = np.nan

df = pd.DataFrame(X, columns=[f"f_{i}" for i in range(100)])
df['target'] = y
df.to_csv('/home/user/data.csv', index=False)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

cat << 'EOF' > /home/user/etl_pipeline.py
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score, KFold
import json
import scipy.stats

# Load data
df = pd.read_csv('/home/user/data.csv')
X = df.drop('target', axis=1)
y = df['target']

# Flawed ETL (Data Leakage)
imputer = SimpleImputer(strategy='mean')
X_imputed = imputer.fit_transform(X)

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_imputed)

model = LogisticRegression(random_state=42, max_iter=1000)

cv = KFold(n_splits=10, shuffle=True, random_state=42)
flawed_scores = cross_val_score(model, X_scaled, y, cv=cv, scoring='roc_auc')
flawed_mean_auc = flawed_scores.mean()

# TODO: Fix the data leakage using a proper Pipeline
# Compute corrected_scores
# Perform paired t-test between flawed_scores and corrected_scores
# Save to /home/user/results.json
EOF

chmod -R 777 /home/user
