#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas numpy scikit-learn setuptools

    # Create vendored package
    mkdir -p /app/datacleaner/datacleaner
    cat << 'EOF' > /app/datacleaner/setup.py
from setuptools import setup, find_packages
setup(name='datacleaner', version='0.1', packages=find_packages(), install_requires=['numpy', 'scikit-learn', 'broken-dep-123'])
EOF
    touch /app/datacleaner/datacleaner/__init__.py
    cat << 'EOF' > /app/datacleaner/datacleaner/utils.py
import numpy as np
def clean_features(X):
    return np.array(X) ** 2
EOF

    # Generate training and verifier data
    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

clean_X = np.random.uniform(-1.5, 1.5, (500, 3))
evil_X = np.random.uniform(2.0, 5.0, (500, 3))
clean_df = pd.DataFrame(clean_X, columns=['f1', 'f2', 'f3'])
clean_df['is_evil'] = 0
evil_df = pd.DataFrame(evil_X, columns=['f1', 'f2', 'f3'])
evil_df['is_evil'] = 1

train_df = pd.concat([clean_df, evil_df]).sample(frac=1).reset_index(drop=True)
train_df.to_csv('/home/user/train_data.csv', index=False)

os.makedirs('/verifier/clean', exist_ok=True)
os.makedirs('/verifier/evil', exist_ok=True)

test_clean = pd.DataFrame(np.random.uniform(-1.0, 1.0, (100, 3)), columns=['f1', 'f2', 'f3'])
test_clean.to_csv('/verifier/clean/clean_data.csv', index=False)

test_evil = pd.DataFrame(np.random.uniform(3.0, 6.0, (100, 3)), columns=['f1', 'f2', 'f3'])
test_evil.to_csv('/verifier/evil/evil_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
