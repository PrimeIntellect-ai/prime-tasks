#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

mkdir -p /home/user

cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Create synthetic data
data = []
base_time = pd.Timestamp("2023-10-01 08:00:00")

trucks = ['TRUCK_A', 'TRUCK_B']

# TRUCK_A: Irregular, needs ffill and interp
data.extend([
    [base_time + timedelta(minutes=0), 'TRUCK_A', -15.0, 60.0],
    [base_time + timedelta(minutes=4), 'TRUCK_A', np.nan, np.nan],
    [base_time + timedelta(minutes=11), 'TRUCK_A', -12.0, 70.0],
    [base_time + timedelta(minutes=65), 'TRUCK_A', -8.0, 80.0],
    [base_time + timedelta(minutes=122), 'TRUCK_A', -16.0, 65.0],
    [base_time + timedelta(minutes=185), 'TRUCK_A', -7.0, 78.0]
])

# TRUCK_B: Missing temps exceeding limit, high speed
data.extend([
    [base_time + timedelta(minutes=0), 'TRUCK_B', -18.0, 65.0],
    [base_time + timedelta(minutes=65), 'TRUCK_B', -18.0, 65.0],
    [base_time + timedelta(minutes=125), 'TRUCK_B', -9.0, 85.0],
    [base_time + timedelta(minutes=185), 'TRUCK_B', -17.0, 60.0]
])

df = pd.DataFrame(data, columns=['timestamp', 'truck_id', 'temperature', 'speed'])
df.to_csv('/home/user/raw_telemetry.csv', index=False)
EOF

python3 /home/user/setup_data.py
rm /home/user/setup_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
