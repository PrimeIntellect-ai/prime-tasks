#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest pandas numpy

mkdir -p /home/user

cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
n = 1000
timestamps = pd.date_range('2023-01-01', periods=n, freq='min')
sensor_ids = np.random.choice([1, 2], size=n)
readings = np.random.normal(loc=100, scale=15, size=n)

# Inject outliers
outlier_indices = [10, 50, 150, 800, 950]
readings[10] = 500
readings[50] = -200
readings[150] = 400
readings[800] = 600
readings[950] = -300

df = pd.DataFrame({'timestamp': timestamps, 'sensor_id': sensor_ids, 'reading': readings})
df.to_csv('/home/user/raw_sensor.csv', index=False)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
