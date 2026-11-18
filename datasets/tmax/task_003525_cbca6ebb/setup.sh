#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install --default-timeout=100 pytest numpy pandas

mkdir -p /app/fast_bayes_infer/fast_bayes_infer
mkdir -p /app/data/clean
mkdir -p /app/data/evil

# Create the broken fast_bayes_infer package
cat << 'EOF' > /app/fast_bayes_infer/setup.py
from setuptools import setup, find_packages

setup(
    name="fast_bayes_infer",
    version="1.0.0",
    packages=find_packages(),
)
EOF

cat << 'EOF' > /app/fast_bayes_infer/fast_bayes_infer/__init__.py
from .inference import GaussianBayes
EOF

cat << 'EOF' > /app/fast_bayes_infer/fast_bayes_infer/inference.py
import numpy as np

class GaussianBayes:
    def __init__(self):
        self.mean = None
        self.cov = None
        self.inv_cov = None
        self.k = None
        self.log_det_cov = None

    def fit(self, X):
        X = np.array(X)
        self.mean = np.mean(X, axis=0)
        self.cov = np.cov(X, rowvar=False)
        self.inv_cov = np.linalg.inv(self.cov)
        self.k = len(self.mean)
        self.log_det_cov = np.log(np.linalg.det(self.cov))

    def log_likelihood(self, X):
        if self.mean is None:
            raise ValueError("Model not fitted")
        X = np.array(X)
        diff = X - self.mean

        # Deliberate bug: matrix multiplication fails for 2D batched arrays
        # Agent must fix this to correctly handle batches
        mahalanobis = diff @ self.inv_cov @ diff

        return -0.5 * (self.k * np.log(2 * np.pi) + self.log_det_cov + mahalanobis)
EOF

# Generate synthetic dataset
cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

# Clean data distribution
clean_train = np.random.normal(0, 1.0, (500, 5))
clean_train_df = pd.DataFrame(clean_train, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
clean_train_df['label'] = 'clean'

# Evil data distribution (anomalous)
evil_train = np.random.normal(4, 1.5, (100, 5))
evil_train_df = pd.DataFrame(evil_train, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
evil_train_df['label'] = 'evil'

# Combine and save train.csv
train_df = pd.concat([clean_train_df, evil_train_df]).sample(frac=1).reset_index(drop=True)
train_df.to_csv('/app/data/train.csv', index=False)

# Generate test files for verifier
clean_test = np.random.normal(0, 1.0, (200, 5))
clean_test_df = pd.DataFrame(clean_test, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
clean_test_df.to_csv('/app/data/clean/test_clean.csv', index=False)

evil_test = np.random.normal(4, 1.5, (200, 5))
evil_test_df = pd.DataFrame(evil_test, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
evil_test_df.to_csv('/app/data/evil/test_evil.csv', index=False)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
