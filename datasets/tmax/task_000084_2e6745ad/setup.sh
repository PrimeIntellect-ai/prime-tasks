#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
pip3 install --no-cache-dir pytest numpy pandas scikit-learn flask fastapi uvicorn cython setuptools wheel

# Create vendored package directory
mkdir -p /app/vendored/fast_bayes

# Create the Cython source file
cat << 'EOF' > /app/vendored/fast_bayes/fast_bayes.pyx
# cython: language_level=3
cimport numpy as np
import numpy as np

class BayesianClassifier:
    def __init__(self, alpha=1.0):
        self.alpha = alpha

    def fit(self, X, y):
        # Dummy implementation for testing
        return self

    def predict_proba(self, X):
        # Dummy implementation returning a fixed probability
        return 0.85
EOF

# Create the broken setup.py file
cat << 'EOF' > /app/vendored/fast_bayes/setup.py
from setuptools import setup, Extension
from Cython.Build import cythonize

ext_modules = [
    Extension(
        "fast_bayes",
        ["fast_bayes.pyx"],
    )
]

setup(
    name="fast_bayes",
    version="1.0.0",
    ext_modules=cythonize(ext_modules),
)
EOF

# Create pyproject.toml to ensure build dependencies are met
cat << 'EOF' > /app/vendored/fast_bayes/pyproject.toml
[build-system]
requires = ["setuptools", "wheel", "Cython", "numpy"]
build-backend = "setuptools.build_meta"
EOF

# Create user
useradd -m -s /bin/bash user || true

# Generate dataset
cat << 'EOF' > /tmp/make_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
X = np.random.randn(100, 4)
y = (X[:, 0] + X[:, 1]*0.5 > 0).astype(int)
df = pd.DataFrame(X, columns=['f1', 'f2', 'f3', 'f4'])
df['target'] = y

os.makedirs('/home/user/data', exist_ok=True)
df.to_csv('/home/user/data/metrics.csv', index=False)
EOF
python3 /tmp/make_data.py

# Set permissions
chmod -R 777 /app
chmod -R 777 /home/user
