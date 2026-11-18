#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 1000

# Generate base features
status = np.random.binomial(1, 0.1, n_samples)
cpu_usage = np.random.normal(50, 10, n_samples) + status * 25
mem_usage = np.random.normal(60, 15, n_samples) + status * 5
disk_io = np.random.lognormal(2, 0.5, n_samples) + status * 10
net_rx = np.random.normal(100, 20, n_samples)
net_tx = np.random.normal(80, 15, n_samples) - status * 20

# Introduce some NaNs
cpu_usage[np.random.choice(n_samples, 20, replace=False)] = np.nan
mem_usage[np.random.choice(n_samples, 15, replace=False)] = np.nan

df = pd.DataFrame({
    'timestamp': pd.date_range('2023-01-01', periods=n_samples, freq='H'),
    'cpu_usage': cpu_usage,
    'mem_usage': mem_usage,
    'disk_io': disk_io,
    'net_rx': net_rx,
    'net_tx': net_tx,
    'status': status
})

df.to_csv('/home/user/server_metrics.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
