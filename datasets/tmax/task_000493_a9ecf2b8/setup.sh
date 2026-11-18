#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
n = 1000
cpu = np.random.normal(50, 15, n)
mem = np.random.normal(60, 20, n)
disk = np.random.exponential(100, n)
net_in = np.random.poisson(500, n)
net_out = np.random.poisson(500, n)

# Introduce correlation and target
crashed = ((cpu > 65) & (mem > 75)).astype(int)

# Introduce NaNs
nan_idx_cpu = np.random.choice(n, 50, replace=False)
cpu[nan_idx_cpu] = np.nan

nan_idx_mem = np.random.choice(n, 50, replace=False)
mem[nan_idx_mem] = np.nan

# Introduce Outliers
outlier_idx_cpu = np.random.choice(n, 10, replace=False)
cpu[outlier_idx_cpu] = 9999

df = pd.DataFrame({
    'cpu_usage': cpu, 
    'mem_usage': mem, 
    'disk_io': disk, 
    'net_in': net_in, 
    'net_out': net_out, 
    'crashed': crashed
})

os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/system_metrics.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
