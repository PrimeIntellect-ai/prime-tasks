#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/experiments

    python3 << 'EOF'
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/experiments', exist_ok=True)

np.random.seed(123)
# Generate train data
X_train = np.random.uniform(-3, 3, 100)
# True underlying function: y = 0.5 * x^3 - 1.2 * x^2 + 2x + 1 + noise
y_train = 0.5 * X_train**3 - 1.2 * X_train**2 + 2 * X_train + 1 + np.random.normal(0, 2, 100)

train_df = pd.DataFrame({'x': X_train, 'y': y_train})
train_df.to_csv('/home/user/data/train.csv', index=False)

# Generate test data
X_test = np.linspace(-3, 3, 20)
test_df = pd.DataFrame({'x': X_test})
test_df.to_csv('/home/user/data/test.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
