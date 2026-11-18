#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    useradd -m -s /bin/bash user || true

    # Generate the initial dataset
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(100)
n_samples = 5000

# Generate Gamma distributed latencies
# Algo A: shape=2, scale=50 (mean 100)
# Algo B: shape=2, scale=45 (mean 90)
latencies_A = np.random.gamma(2, 50, n_samples)
latencies_B = np.random.gamma(2, 45, n_samples)

df_A = pd.DataFrame({'algorithm': 'A', 'latency_ms': latencies_A})
df_B = pd.DataFrame({'algorithm': 'B', 'latency_ms': latencies_B})

df = pd.concat([df_A, df_B]).sample(frac=1, random_state=100).reset_index(drop=True)

df.to_csv('/home/user/server_metrics.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
