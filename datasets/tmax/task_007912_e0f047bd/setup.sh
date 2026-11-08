#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest pandas numpy

mkdir -p /home/user/data

cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)
n_samples = 500

cpu_load = np.random.uniform(10, 100, n_samples)
temperature = np.random.uniform(30, 90, n_samples)
fan_speed = np.random.uniform(1000, 5000, n_samples)

# Insert missing values in fan_speed
missing_indices = np.random.choice(n_samples, size=50, replace=False)
fan_speed[missing_indices] = np.nan

# True formula
power_consumption = (2.5 * cpu_load) + (1.2 * temperature) + (0.05 * np.nan_to_num(fan_speed, nan=np.nanmedian(fan_speed))) + np.random.normal(0, 5, n_samples)

df = pd.DataFrame({
    'cpu_load': cpu_load,
    'temperature': temperature,
    'fan_speed': fan_speed,
    'power_consumption': power_consumption
})

df.to_csv('/home/user/data/metrics.csv', index=False)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
