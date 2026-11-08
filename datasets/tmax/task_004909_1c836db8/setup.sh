#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(123)

n_samples = 5000
labels = np.random.choice([0, 1], size=n_samples, p=[0.7, 0.3])
data = {'id': np.arange(1, n_samples + 1), 'label': labels}

for i in range(1, 21):
    if i == 5:
        data[f'f{i}'] = np.where(labels == 1, np.random.normal(5, 1, n_samples), np.random.normal(0, 1, n_samples))
    elif i == 12:
        data[f'f{i}'] = np.where(labels == 1, np.random.normal(2, 1.5, n_samples), np.random.normal(0, 1.5, n_samples))
    elif i == 18:
        data[f'f{i}'] = np.where(labels == 1, np.random.normal(1, 2, n_samples), np.random.normal(0, 2, n_samples))
    else:
        data[f'f{i}'] = np.random.normal(0, 3, n_samples)

df = pd.DataFrame(data)
df.to_csv('/home/user/data/raw_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
