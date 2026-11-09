#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest scikit-learn pandas flask fastapi uvicorn requests

mkdir -p /app/vendored/datacleaner-1.0.0/datacleaner

cat << 'EOF' > /app/vendored/datacleaner-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name='datacleaner',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['scikit-learn'],
)
EOF

cat << 'EOF' > /app/vendored/datacleaner-1.0.0/datacleaner/__init__.py
from .core import prepare_and_split
EOF

cat << 'EOF' > /app/vendored/datacleaner-1.0.0/datacleaner/core.py
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split

def prepare_and_split(X, y, test_size=0.2, random_state=42):
    scaler = StandardScaler()
    # BUG: Fitting on the whole dataset causes leakage
    X_scaled = scaler.fit_transform(X)
    X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=test_size, random_state=random_state)
    return X_train, X_test, y_train, y_test, scaler
EOF

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
df = pd.DataFrame({
    'num_samples': np.random.randint(100, 10000, n),
    'num_features': np.random.randint(5, 100, n),
    'missing_ratio': np.random.uniform(0, 0.5, n),
    'variance_score': np.random.uniform(0.1, 5.0, n),
    'category': np.random.randint(0, 2, n)
})
df.to_csv('/home/user/data/raw_datasets.csv', index=False)
EOF

python3 /home/user/data/generate_data.py
rm /home/user/data/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
