#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/input /home/user/output

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/input', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

# Generate synthetic data
data = [
    {"timestamp": "2023-10-01 10:00:15", "sensor_id": "S1", "temperature": 20.0},
    {"timestamp": "2023-10-01 10:00:45", "sensor_id": "S1", "temperature": 20.2}, # mean 20.1 for 10:00
    {"timestamp": "2023-10-01 10:01:05", "sensor_id": "S1", "temperature": 20.2},
    {"timestamp": "2023-10-01 10:02:00", "sensor_id": "S1", "temperature": 20.4},
    {"timestamp": "2023-10-01 10:03:00", "sensor_id": "S1", "temperature": 20.5},
    {"timestamp": "2023-10-01 10:04:00", "sensor_id": "S1", "temperature": 20.6},
    # gap at 10:05
    {"timestamp": "2023-10-01 10:06:00", "sensor_id": "S1", "temperature": 20.8}, # interpolated 10:05 to 20.7
    {"timestamp": "2023-10-01 10:07:00", "sensor_id": "S1", "temperature": 20.9},
    {"timestamp": "2023-10-01 10:08:00", "sensor_id": "S1", "temperature": 21.0},
    {"timestamp": "2023-10-01 10:09:00", "sensor_id": "S1", "temperature": 100.0}, # anomaly! mean of previous ~20.5. 
    {"timestamp": "2023-10-01 10:10:00", "sensor_id": "S1", "temperature": 21.2},
    {"timestamp": "2023-10-01 10:11:00", "sensor_id": "S1", "temperature": 21.3},
    # long gap 10:12 to 10:20 (>5 mins) -> NaNs
    {"timestamp": "2023-10-01 10:20:00", "sensor_id": "S1", "temperature": 22.0},
    {"timestamp": "2023-10-01 11:00:00", "sensor_id": "S1", "temperature": 23.0},
    {"timestamp": "2023-10-01 11:01:00", "sensor_id": "S1", "temperature": 23.5},
]

df = pd.DataFrame(data)
df.to_csv('/home/user/input/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
