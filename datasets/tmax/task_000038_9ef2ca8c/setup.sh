#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)

dates = pd.date_range(start='2023-01-01', periods=30, freq='D')
raw_data = []

for d in dates:
    # 100 readings per day
    readings = np.random.normal(loc=50.0, scale=5.0, size=100)
    for i, r in enumerate(readings):
        raw_data.append({'date': d.strftime('%Y-%m-%d'), 'sensor_id': f'S_{i}', 'reading': r})

df_raw = pd.DataFrame(raw_data)
df_raw.to_csv('/home/user/raw_sensor_data.csv', index=False)

# Calculate true means
true_means = df_raw.groupby('date')['reading'].mean().reset_index()

# Generate legacy means with a slight systematic bias and noise
legacy_data = []
for _, row in true_means.iterrows():
    noise = np.random.normal(loc=0.5, scale=0.1)
    legacy_mean = row['reading'] + noise
    legacy_data.append({'date': row['date'], 'legacy_mean': legacy_mean})

df_legacy = pd.DataFrame(legacy_data)
df_legacy.to_csv('/home/user/legacy_daily_summary.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
