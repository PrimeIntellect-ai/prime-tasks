#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data/raw', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

np.random.seed(10)
n = 500

cpu = np.random.normal(50, 20, n)
ram = 30 + 0.4 * cpu + np.random.normal(0, 10, n)
disk = np.random.exponential(50, n)
net = 10 + 0.5 * cpu + 0.2 * ram + 0.8 * disk + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'cpu_usage': cpu,
    'ram_usage': ram,
    'disk_io': disk,
    'net_tx': net
})

# Inject invalid rows for schema enforcement
df.loc[10, 'cpu_usage'] = 150.0
df.loc[25, 'ram_usage'] = -5.0
df.loc[50, 'disk_io'] = -10.0
df.loc[100, 'cpu_usage'] = np.nan

df.to_csv('/home/user/data/raw/metrics.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
