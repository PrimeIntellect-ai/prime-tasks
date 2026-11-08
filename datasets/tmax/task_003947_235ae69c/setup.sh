#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)

def generate_data(filename, mean_lat, std_lat, n=10000):
    latencies = np.random.normal(mean_lat, std_lat, n)

    # Add outliers
    latencies[np.random.choice(n, 50, replace=False)] = 5000.0 + np.random.uniform(0, 1000, 50) # cold starts
    latencies[np.random.choice(n, 20, replace=False)] = -10.0 # logging errors

    df = pd.DataFrame({
        'request_id': [f"req_{i}" for i in range(n)],
        'latency_ms': latencies
    })

    # Add missing values
    missing_idx = np.random.choice(n, 100, replace=False)
    df.loc[missing_idx, 'latency_ms'] = np.nan

    df.to_csv(filename, index=False)

os.makedirs('/home/user', exist_ok=True)
generate_data('/home/user/model_v1.csv', 150.0, 20.0, 10000)
generate_data('/home/user/model_v2.csv', 148.0, 25.0, 10000)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
