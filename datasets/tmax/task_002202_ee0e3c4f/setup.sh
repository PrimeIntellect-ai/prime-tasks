#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn joblib

mkdir -p /home/user/mlops_experiment

python3 -c "
import os
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification

os.makedirs('/home/user/mlops_experiment', exist_ok=True)

# 1. Create dataset with missing values
X, y = make_classification(n_samples=1000, n_features=20, random_state=42)
# Introduce missing values
rng = np.random.RandomState(42)
missing_mask = rng.rand(*X.shape) < 0.1
X[missing_mask] = np.nan

df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(20)])
df['target'] = y
df.to_csv('/home/user/mlops_experiment/data.csv', index=False)

# 2. Create buggy train.py
buggy_code = \"\"\"import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.ensemble import RandomForestClassifier
import json
import joblib

# Load data
df = pd.read_csv('/home/user/mlops_experiment/data.csv')
X = df.drop('target', axis=1)
y = df['target']

# BUG: Data leakage (fit_transform on all data)
imputer = SimpleImputer(strategy='mean')
X_imputed = imputer.fit_transform(X)

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_imputed)

# Split after scaling
X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

# Train model
clf = RandomForestClassifier(random_state=42)
clf.fit(X_train, y_train)

# Evaluate
acc = clf.score(X_test, y_test)
print(f\"Accuracy: {acc}\")
\"\"\"

with open('/home/user/mlops_experiment/train.py', 'w') as f:
    f.write(buggy_code)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
