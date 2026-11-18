#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 200
temp = np.random.uniform(10, 30, n)
humid = np.random.uniform(30, 80, n)
sensor_1 = np.random.normal(0, 1.414, n)
sensor_2 = sensor_1 * 0.9 + np.random.normal(0, 0.5, n) 
sensor_2 = sensor_2 * 2.0
sensor_3 = np.random.normal(5, 2, n)

temp_humid_idx = temp * humid
yield_val = 3.0 * sensor_2 + 1.5 * sensor_3 + 0.05 * temp_humid_idx + np.random.normal(0, 1, n)

df = pd.DataFrame({
    'sensor_1': sensor_1,
    'sensor_2': sensor_2,
    'sensor_3': sensor_3,
    'temperature': temp,
    'humidity': humid,
    'yield': yield_val
})
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
