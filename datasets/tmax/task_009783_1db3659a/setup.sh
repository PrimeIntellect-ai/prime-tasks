#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw
    mkdir -p /home/user/data/processed

    cat << 'EOF' > /tmp/setup_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data/raw', exist_ok=True)
os.makedirs('/home/user/data/processed', exist_ok=True)

np.random.seed(123)
for i in range(3):
    n_rows = 100
    data = {
        'timestamp': pd.date_range(start=f'2023-01-0{i+1}', periods=n_rows, freq='h'),
        'machine_id': [f'M{i}'] * n_rows
    }
    for j in range(1, 21):
        data[f'sensor_{j}'] = np.random.randn(n_rows) * 10 + 50

    df = pd.DataFrame(data)

    # Introduce NaNs and negative values for filtering
    if i == 0:
        df.loc[5, 'sensor_1'] = np.nan
        df.loc[10, 'sensor_1'] = -5.0
    if i == 1:
        df.loc[50, 'sensor_5'] = np.nan

    df.to_csv(f'/home/user/data/raw/machine_{i}.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
