#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user/sensor_data', exist_ok=True)

# Dataset 1: S01
df1 = pd.DataFrame({
    'timestamp': range(1, 11),
    'sensor_id': ['S01']*10,
    'temperature': [20.0, np.nan, 24.0, 25.0, np.nan, 29.0, 30.0, 35.0, 36.0, 37.0],
    'vibration': [10.0, 11.0, np.nan, 13.0, 14.0, 15.0, np.nan, 17.0, 18.0, 19.0]
})
df1.to_csv('/home/user/sensor_data/S01_data.csv', index=False)

# Dataset 2: S02
df2 = pd.DataFrame({
    'timestamp': range(1, 11),
    'sensor_id': ['S02']*10,
    'temperature': [np.nan, 10.0, 12.0, 15.0, 20.0, 20.0, 25.0, np.nan, 30.0, np.nan],
    'vibration': [5.0, 6.0, 7.0, 8.0, np.nan, np.nan, 11.0, 12.0, 13.0, 14.0]
})
df2.to_csv('/home/user/sensor_data/S02_data.csv', index=False)

# Dataset 3: S03
df3 = pd.DataFrame({
    'timestamp': range(1, 11),
    'sensor_id': ['S03']*10,
    'temperature': [50.0, 48.0, 46.0, 44.0, 42.0, np.nan, 38.0, 36.0, 34.0, 32.0],
    'vibration': [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
})
df3.to_csv('/home/user/sensor_data/S03_data.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
