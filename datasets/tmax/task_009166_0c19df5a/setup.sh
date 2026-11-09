#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import os

np.random.seed(42)
base_time = pd.Timestamp("2023-10-01 00:00:00")
# Generate 5 days of data
timestamps = [base_time + pd.Timedelta(minutes=5*i + np.random.randint(-2, 3)) for i in range(1440)]

data = []
for ts in timestamps:
    for sensor in ['S1', 'S2']:
        temp = 20 + 5 * np.sin(ts.hour * np.pi / 12) + np.random.normal(0, 0.5)
        hum = 50 + 10 * np.cos(ts.hour * np.pi / 12) + np.random.normal(0, 1)

        # Introduce NaNs
        if np.random.random() < 0.15: temp = np.nan
        if np.random.random() < 0.15: hum = np.nan

        data.append({'timestamp': ts.isoformat(), 'sensor_id': sensor, 'temperature': temp, 'humidity': hum})

df = pd.DataFrame(data)
# Add some complete gaps
df = df.drop(df.index[50:70])

os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/raw_sensor_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
