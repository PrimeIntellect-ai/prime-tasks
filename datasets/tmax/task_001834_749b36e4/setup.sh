#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

timestamps = np.linspace(0, 10, 101) # 101 points from 0 to 10
data = []

for s_id, func in [('A', lambda t: np.sin(t) + 2), 
                   ('B', lambda t: 0.5 * t), 
                   ('C', lambda t: np.full_like(t, 1.5))]:
    values = func(timestamps)

    # Inject Noise
    values += np.random.normal(0, 0.1, size=len(timestamps))

    # Inject Outliers
    outlier_idx = np.random.choice(len(timestamps), size=3, replace=False)
    values[outlier_idx] += 20.0 * np.random.choice([-1, 1], size=3)

    # Inject NaNs
    nan_idx = np.random.choice(len(timestamps), size=5, replace=False)
    values[nan_idx] = np.nan

    for t, v in zip(timestamps, values):
        data.append({'timestamp': t, 'sensor_id': s_id, 'value': v})

df = pd.DataFrame(data)
df = df.sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
