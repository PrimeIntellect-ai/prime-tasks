#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

# Create synthetic dataset
np.random.seed(123)
n_samples = 1000
n_features = 50

# Generate timestamps
start_time = datetime(2023, 1, 1)
timestamps = [start_time + timedelta(hours=i) for i in range(n_samples)]

# Generate features with some covariance
X = np.random.randn(n_samples, n_features)
# Add some signal for the minority class
y = np.zeros(n_samples, dtype=int)
minority_indices = np.random.choice(n_samples, size=50, replace=False)
y[minority_indices] = 1

# Shift mean of minority class features
X[minority_indices, :5] += 2.0

df = pd.DataFrame(X, columns=[f'sensor_{i+1}' for i in range(n_features)])
df.insert(0, 'timestamp', timestamps)
df['failure'] = y

os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
