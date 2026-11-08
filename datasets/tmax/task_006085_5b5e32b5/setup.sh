#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas matplotlib scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
times = np.arange(100)
sensors = ['S1', 'S2', 'S3', 'S4', 'S5']

# Rank 2 underlying signal
t = times / 10.0
s1 = np.sin(t)
s2 = np.cos(t)

# Mixing matrix
mix = np.random.randn(2, 5)
clean_data = np.vstack((s1, s2)).T @ mix

# Add noise
noise = np.random.randn(100, 5) * 0.1
data = clean_data + noise

df = pd.DataFrame(data, columns=sensors)
df['time'] = times

# Melt to long format and shuffle
df_long = df.melt(id_vars=['time'], var_name='sensor', value_name='reading')
df_long = df_long.sample(frac=1, random_state=42).reset_index(drop=True)

# Save to expected path
df_long.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
