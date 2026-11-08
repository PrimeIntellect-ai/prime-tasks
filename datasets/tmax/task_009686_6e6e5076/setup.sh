#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/setup_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

# Generate deterministic input data
np.random.seed(42)
timestamps = pd.date_range("2023-01-01", periods=100, freq="h")
sensor_A = np.random.normal(10, 2, 100)
# Make sensor_B highly correlated with sensor_A (> 0.90)
sensor_B = sensor_A * 0.95 + np.random.normal(0, 0.3, 100) 
sensor_C = np.random.normal(20, 5, 100)

df = pd.DataFrame({
    'timestamp': timestamps,
    'sensor_A': sensor_A,
    'sensor_B': sensor_B,
    'sensor_C': sensor_C
})

df.to_csv('/home/user/data/sensor_readings.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
