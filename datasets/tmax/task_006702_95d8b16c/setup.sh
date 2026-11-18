#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 1000

failure = np.random.binomial(n=1, p=0.2, size=n_samples)
cpu_usage = np.random.normal(loc=50, scale=15, size=n_samples) + failure * 10
memory_usage = np.random.normal(loc=60, scale=20, size=n_samples) + failure * 15
disk_io = np.random.normal(loc=100, scale=30, size=n_samples)
temperature = np.random.normal(loc=40, scale=5, size=n_samples) + failure * 6

df = pd.DataFrame({
    'cpu_usage': cpu_usage,
    'memory_usage': memory_usage,
    'disk_io': disk_io,
    'temperature': temperature,
    'failure': failure
})

df.to_csv('/home/user/server_metrics.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
