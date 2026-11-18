#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
sensors = pd.DataFrame({
    'sensor_id': range(1, 101),
    'model_type': np.random.choice(['Alpha', 'Beta'], 100)
})

# Generate readings
readings = pd.DataFrame({
    'sensor_id': np.random.choice(range(1, 101), 1000),
    'reading_time_ms': np.random.normal(50, 10, 1000),
    'value': np.random.random(1000)
})

# Introduce a difference for Alpha models
alpha_ids = sensors[sensors['model_type'] == 'Alpha']['sensor_id']
readings.loc[readings['sensor_id'].isin(alpha_ids), 'reading_time_ms'] += 5.0

sensors.to_csv('/home/user/sensors.csv', index=False)
readings.to_csv('/home/user/readings.csv', index=False)
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
