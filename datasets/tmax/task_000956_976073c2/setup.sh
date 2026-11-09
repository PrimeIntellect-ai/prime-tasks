#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 1000

data = {
    'sensor_1': np.random.normal(0, 1, n_samples),
    'sensor_2': np.random.normal(5, 2, n_samples),
    'sensor_3': np.random.normal(-2, 1.5, n_samples),
    'sensor_4': np.random.uniform(0, 10, n_samples),
    'sensor_5': np.random.normal(10, 5, n_samples)
}

# Create target based on some linear combination
logits = (data['sensor_1'] * 1.5 + 
          (data['sensor_2'] - 5) * -0.8 + 
          data['sensor_3'] * 0.5 + 
          np.random.normal(0, 1, n_samples))
probs = 1 / (1 + np.exp(-logits))
data['target'] = (probs > 0.5).astype(int)

df = pd.DataFrame(data)

# Introduce missing values in sensor_3
missing_idx = np.random.choice(n_samples, size=50, replace=False)
df.loc[missing_idx, 'sensor_3'] = np.nan

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
