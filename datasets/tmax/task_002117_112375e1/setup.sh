#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

# Generate sensor_data.csv
sensor_data = pd.DataFrame([
    {'timestamp': '2023-10-01T10:15:00Z', 'sensor_id': 'S1', 'temperature': 22.5, 'humidity': 45.0},
    {'timestamp': '2023-10-01T10:45:00Z', 'sensor_id': 'S1', 'temperature': 23.5, 'humidity': 47.0},
    {'timestamp': '2023-10-01T10:30:00Z', 'sensor_id': 'S2', 'temperature': 18.0, 'humidity': 55.0},
    # Invalid rows
    {'timestamp': '2023-10-01T10:50:00Z', 'sensor_id': 'S1', 'temperature': 60.0, 'humidity': 45.0}, # Temp too high
    {'timestamp': '2023-10-01T11:05:00Z', 'sensor_id': 'S2', 'temperature': 19.0, 'humidity': -5.0},  # Hum too low
    {'timestamp': '2023-10-01T11:20:00Z', 'sensor_id': 'S2', 'temperature': np.nan, 'humidity': 50.0}, # Missing value
    # Hour 11 valid
    {'timestamp': '2023-10-01T11:15:00Z', 'sensor_id': 'S1', 'temperature': 24.0, 'humidity': 46.0},
    {'timestamp': '2023-10-01T11:30:00Z', 'sensor_id': 'S2', 'temperature': 19.5, 'humidity': 52.0},
])
sensor_data.to_csv('/home/user/sensor_data.csv', index=False)

# Generate maintenance.csv
maintenance = pd.DataFrame([
    {'hour': '2023-10-01T10:00:00Z', 'sensor_id': 'S1', 'status': 'active'},
    {'hour': '2023-10-01T11:00:00Z', 'sensor_id': 'S2', 'status': 'maintenance'},
])
maintenance.to_csv('/home/user/maintenance.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
