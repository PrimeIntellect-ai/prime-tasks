#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/data/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
n_samples = 1000

cpu_load = np.random.uniform(0, 100, n_samples)
memory_usage = np.random.uniform(1, 16, n_samples)
network_io = np.random.exponential(100, n_samples)

# Induce NaNs in memory_usage
nan_indices = np.random.choice(n_samples, size=50, replace=False)
memory_usage[nan_indices] = np.nan

# Base target
response_time = 10 + 0.5 * cpu_load + 2.0 * np.nan_to_num(memory_usage, nan=8.0) + 0.05 * network_io + np.random.normal(0, 5, n_samples)

# Induce extreme outliers
outlier_indices = np.random.choice(n_samples, size=15, replace=False)
response_time[outlier_indices] += np.random.uniform(500, 1000, size=15)

df = pd.DataFrame({
    'cpu_load': cpu_load,
    'memory_usage': memory_usage,
    'network_io': network_io,
    'response_time': response_time
})

df.to_csv('/home/user/data/server_metrics.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
