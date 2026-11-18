#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/output/cleaned

    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
timestamps = np.arange(0, 100)

def generate_sensor(filename, base_temp, missing_rate):
    temp = base_temp + np.random.normal(0, 0.5, 100)
    moisture = np.random.uniform(30, 60, 100)

    # Introduce missing values
    missing_idx = np.random.choice(100, size=int(100 * missing_rate), replace=False)
    temp_with_nans = temp.copy()
    temp_with_nans[missing_idx] = np.nan

    df = pd.DataFrame({'timestamp': timestamps, 'temperature': temp_with_nans, 'moisture': moisture})
    df.to_csv(f'/home/user/raw_data/{filename}', index=False)
    return temp

# Sensor 1: Base profile 1 (0% missing)
t1 = generate_sensor('sensor_01.csv', 20 + 5 * np.sin(timestamps / 10.0), 0.0)

# Sensor 2: Base profile 2 (10% missing) - Different from profile 1
t2 = generate_sensor('sensor_02.csv', 25 + 5 * np.cos(timestamps / 10.0), 0.1)

# Sensor 3: Base profile 1 (45% missing) - SHOULD BE REJECTED (>30%)
t3 = generate_sensor('sensor_03.csv', 20 + 5 * np.sin(timestamps / 10.0), 0.45)

# Sensor 4: Base profile 1 + small noise (5% missing) - Similar to Sensor 1
t4 = generate_sensor('sensor_04.csv', 20 + 5 * np.sin(timestamps / 10.0) + np.random.normal(0, 0.2, 100), 0.05)

# Sensor 5: Base profile 2 + small noise (5% missing) - Similar to Sensor 2
t5 = generate_sensor('sensor_05.csv', 25 + 5 * np.cos(timestamps / 10.0) + np.random.normal(0, 0.2, 100), 0.05)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
