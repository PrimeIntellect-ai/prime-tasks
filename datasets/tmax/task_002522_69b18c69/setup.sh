#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd

os.makedirs("/home/user", exist_ok=True)

# Generate synthetic data
np.random.seed(42)

# Train data: N=100
train_data = {
    'feature_1': np.random.normal(loc=10, scale=2, size=100),
    'feature_2': np.random.normal(loc=5, scale=1.5, size=100),
    'feature_3': np.random.normal(loc=20, scale=5, size=100)
}
df_train = pd.DataFrame(train_data)
df_train.to_csv("/home/user/train.csv", index=False)

# Test data: N=50, drawn from a slightly shifted distribution to amplify leakage differences
test_data = {
    'feature_1': np.random.normal(loc=11, scale=2.5, size=50),
    'feature_2': np.random.normal(loc=4.5, scale=1.2, size=50),
    'feature_3': np.random.normal(loc=22, scale=4, size=50)
}
df_test = pd.DataFrame(test_data)
df_test.to_csv("/home/user/test.csv", index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
