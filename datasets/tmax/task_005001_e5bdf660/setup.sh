#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow

    useradd -m -s /bin/bash user || true

    # Create the data generation script
    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

os.makedirs('/home/user/sensor_data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

start_time = datetime(2023, 1, 1, 0, 0, 0)

# Sensor A (UTF-8, clean, 2-min intervals)
times_a = [start_time + timedelta(minutes=2*i) for i in range(60)]
df_a = pd.DataFrame({
    'timestamp': times_a,
    'sensor_id': 'sensor_A',
    'temperature': np.random.uniform(20.0, 25.0, 60),
    'humidity': np.random.uniform(40.0, 50.0, 60)
})
df_a.to_csv('/home/user/sensor_data/sensor_A.csv', index=False, encoding='utf-8')

# Sensor B (UTF-16, dirty temp, 3-min intervals)
times_b = [start_time + timedelta(minutes=3*i) for i in range(40)]
df_b = pd.DataFrame({
    'timestamp': times_b,
    'sensor_id': 'sensor_B',
    'temperature': np.random.uniform(30.0, 35.0, 40),
    'humidity': np.random.uniform(50.0, 60.0, 40)
})
# Inject invalid records
df_b.loc[5, 'temperature'] = 200.0
df_b.loc[10, 'humidity'] = -10.0
df_b.to_csv('/home/user/sensor_data/sensor_B.csv', index=False, encoding='utf-16')

# Sensor C (ISO-8859-1, gaps, 7-min intervals)
times_c = [start_time + timedelta(minutes=7*i) for i in range(17)]
df_c = pd.DataFrame({
    'timestamp': times_c,
    'sensor_id': 'sensor_C',
    'temperature': np.random.uniform(10.0, 15.0, 17),
    'humidity': np.random.uniform(70.0, 80.0, 17)
})
df_c.to_csv('/home/user/sensor_data/sensor_C.csv', index=False, encoding='iso-8859-1')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
