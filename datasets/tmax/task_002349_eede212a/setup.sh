#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
X = np.random.randint(1, 100, 500)
Y = np.random.randint(10, 1000, 500)

a_true = 2.5
b_true = 0.5
c_true = 0.01
d_true = 10.0

# Generate latency with noise
L = a_true * X + b_true * Y + c_true * X * Y + d_true + np.random.normal(0, 5.0, 500)

df = pd.DataFrame({'concurrency': X, 'data_size_kb': Y, 'latency_ms': L})

# Inject timeouts (outliers)
outlier_indices = np.random.choice(df.index, size=25, replace=False)
df.loc[outlier_indices, 'latency_ms'] = 9999.5

df.to_csv('/home/user/perf_logs.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
