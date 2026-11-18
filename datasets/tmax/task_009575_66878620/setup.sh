#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

def generate_server_data(n_samples):
    cpu_usage = np.random.uniform(10, 90, n_samples)
    memory_usage = np.random.uniform(10, 90, n_samples)
    disk_io = np.random.normal(100, 20, n_samples)
    network_in = np.random.exponential(50, n_samples)
    network_out = np.random.exponential(50, n_samples)

    # Introduce a rule for crashes
    # high cpu/mem ratio or extreme disk_io increases crash probability
    ratio = cpu_usage / memory_usage
    prob = 1 / (1 + np.exp(-(ratio - 2.0) * 3 - (disk_io - 150) * 0.05))
    crash = (np.random.rand(n_samples) < prob).astype(int)

    # Artificially lower crash rate to make it imbalanced
    crash[np.random.rand(n_samples) < 0.8] = 0

    df = pd.DataFrame({
        'cpu_usage': cpu_usage,
        'memory_usage': memory_usage,
        'disk_io': disk_io,
        'network_in': network_in,
        'network_out': network_out,
        'crash': crash
    })
    return df

df1 = generate_server_data(400)
df2 = generate_server_data(500)
df3 = generate_server_data(300)

df1.to_csv('/home/user/data/server_1.csv', index=False)
df2.to_csv('/home/user/data/server_2.csv', index=False)
df3.to_csv('/home/user/data/server_3.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
