#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(100)
n_samples = 1000

data = {
    'sensor_id': np.random.randint(1, 10, n_samples),
    'temperature': np.random.normal(50, 10, n_samples),
    'vibration': np.random.normal(5, 2, n_samples),
    'pressure': np.random.normal(100, 15, n_samples),
}

# Add correlations
data['status'] = (data['temperature'] > 55).astype(int)
data['remaining_life'] = 1000 - (data['temperature'] * 5 + data['vibration'] * 10 + np.random.normal(0, 20, n_samples))

df = pd.DataFrame(data)

# Inject missing values
df.loc[np.random.choice(df.index, 50, replace=False), 'temperature'] = np.nan
df.loc[np.random.choice(df.index, 100, replace=False), 'vibration'] = np.nan

df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
