#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(100)

n_A = 120
n_B = 130

# Base distributions
latency_A = np.random.normal(loc=45.0, scale=5.0, size=n_A)
latency_B = np.random.normal(loc=52.0, scale=6.0, size=n_B)

# Add anomalies to A
latency_A[5] = -10.5 # clock sync
latency_A[12] = np.nan
latency_A[45] = 200.0 # cold start outlier
latency_A[60] = 195.0

# Add anomalies to B
latency_B[10] = -2.0
latency_B[22] = np.nan
latency_B[23] = np.nan
latency_B[80] = 300.0
latency_B[100] = 280.0

df_A = pd.DataFrame({'req_id': [f"A_{i}" for i in range(n_A)], 'model': 'A', 'latency': latency_A})
df_B = pd.DataFrame({'req_id': [f"B_{i}" for i in range(n_B)], 'model': 'B', 'latency': latency_B})

df = pd.concat([df_A, df_B]).sample(frac=1, random_state=42).reset_index(drop=True)

# Replace some NaNs with string NA for bash testing
df['latency'] = df['latency'].apply(lambda x: 'NA' if pd.isna(x) else round(x, 2))

os.makedirs("/home/user", exist_ok=True)
df.to_csv("/home/user/inference_logs.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
