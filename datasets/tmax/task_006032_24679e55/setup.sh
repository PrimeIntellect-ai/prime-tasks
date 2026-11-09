#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

# Create synthetic data
np.random.seed(123)
n_samples = 10000

data = {
    'transaction_id': [f"TXN_{i:05d}" for i in range(n_samples)],
    'amount': np.random.exponential(scale=100, size=n_samples),
    'duration': np.random.normal(loc=50, scale=10, size=n_samples),
    'location_score': np.random.uniform(0, 100, size=n_samples),
    'network_latency': np.random.lognormal(mean=2, sigma=0.5, size=n_samples),
    'device_trust': np.random.beta(a=5, b=2, size=n_samples) * 100
}

# Inject some clear anomalies
anomaly_indices = np.random.choice(n_samples, size=300, replace=False)
data['amount'][anomaly_indices] *= 10
data['network_latency'][anomaly_indices] *= 5

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_transactions.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
