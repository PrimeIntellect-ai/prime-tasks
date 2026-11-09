#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest pandas numpy

mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)

# Generate valid dates
dates = pd.date_range(start="2023-10-01 00:00:00", periods=50, freq="15min")

data = []
for i, dt in enumerate(dates):
    # Create some valid data
    sensor_id = np.random.randint(1, 11)
    temp = 22.0 + np.random.normal(0, 1.5)
    pres = 101.3 + np.random.normal(0, 2.0)
    data.append([dt.strftime("%Y-%m-%dT%H:%M:%SZ"), sensor_id, temp, pres])

# Add some invalid data to test schema enforcement
data.append(["2023-10-01T02:05:00Z", 15, 25.0, 100.0]) # Invalid sensor_id
data.append(["2023-10-01T02:15:00Z", 5, 200.0, 100.0]) # Invalid temp
data.append(["2023-10-01T02:25:00Z", 5, 25.0, -10.0])  # Invalid pressure
data.append(["invalid_date", 5, 25.0, 100.0])          # Invalid date

df = pd.DataFrame(data, columns=["timestamp", "sensor_id", "temperature_raw", "pressure_raw"])

# Shuffle
df = df.sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv("/home/user/data/raw_sensors.csv", index=False)
EOF

python3 /home/user/data/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
