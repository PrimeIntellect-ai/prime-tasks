#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create data directory
    mkdir -p /home/user/data

    # Generate the dataset
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(123)
n = 10000

timestamps = pd.date_range(start='2023-01-01', periods=n, freq='1H')
s1 = np.random.normal(10, 2, n)
s2 = np.random.normal(-5, 5, n)
s3 = np.random.exponential(1, n)
s4 = np.random.uniform(0, 100, n)
s5 = s1 * 0.5 + s2 * 0.2 + np.random.normal(0, 1, n)

# Inject missing values
for col in [s1, s2, s3, s4, s5]:
    mask = np.random.rand(n) < 0.05
    col[mask] = np.nan

# Target generation (based on hour and components)
hour = timestamps.hour
target = 3.5 * hour + 2.0 * np.nan_to_num(s1) - 1.5 * np.nan_to_num(s3) + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'timestamp': timestamps,
    's1': s1,
    's2': s2,
    's3': s3,
    's4': s4,
    's5': s5,
    'target': target
})

# Inject outliers
df.loc[10:20, 's1'] = 1000
df.loc[50:60, 's2'] = -1000

df.to_csv('/home/user/data/sensor_readings.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
