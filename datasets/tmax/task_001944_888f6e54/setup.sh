#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn fastapi uvicorn requests joblib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
n_rows = 5000
sensor_ids = np.random.randint(1, 21, size=n_rows)
timestamps = pd.date_range(start='2023-01-01', periods=n_rows, freq='T')
temperature = np.random.normal(50, 10, size=n_rows)
vibration = np.random.normal(5, 2, size=n_rows)
pressure = np.random.normal(100, 15, size=n_rows)

# Generate a synthetic target
status = ((temperature > 55) & (vibration > 6)).astype(int)

df = pd.DataFrame({
    'timestamp': timestamps,
    'sensor_id': sensor_ids,
    'temperature': temperature,
    'vibration': vibration,
    'pressure': pressure,
    'status': status
})

# Shuffle to make sorting necessary
df = df.sample(frac=1, random_state=42).reset_index(drop=True)

# Save to expected location
os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/raw_sensors.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
