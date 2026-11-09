#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scipy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
timestamps = pd.date_range('2023-01-01', periods=n, freq='h')
sensor_ids = np.random.choice(['S1', 'S2', 'S3'], size=n)
temp = np.random.normal(20, 10, size=n)
pressure = np.random.normal(1013, 10, size=n)
humidity = np.random.normal(50, 15, size=n)

# introduce noise/missing
temp[10:20] = np.nan
temp[50] = 200 # outlier
temp[100] = -100 # outlier

missing_pressure_idx = np.random.choice(n, 50, replace=False)
missing_humidity_idx = np.random.choice(n, 50, replace=False)

pressure[missing_pressure_idx] = np.nan
humidity[missing_humidity_idx] = np.nan

df = pd.DataFrame({
    'timestamp': timestamps,
    'sensor_id': sensor_ids,
    'temp': temp,
    'pressure': pressure,
    'humidity': humidity
})

df.to_csv('/home/user/raw_sensors.csv', index=False)

# Clean logic for baseline to generate accurate baseline predictions
df_clean = df.dropna(subset=['temp']).copy()
df_clean = df_clean[(df_clean['temp'] >= -50) & (df_clean['temp'] <= 150)].copy()

df_clean['pressure'] = df_clean.groupby('sensor_id')['pressure'].transform(lambda x: x.fillna(x.median()))
df_clean['humidity'] = df_clean['humidity'].fillna(df_clean['humidity'].mean())

power_output = 0.5 * df_clean['temp'] + 0.2 * df_clean['pressure'] - 0.1 * df_clean['humidity'] + 5.0

# Baseline with slight noise
np.random.seed(123)
baseline_power = power_output + np.random.normal(0, 0.05, size=len(df_clean))

df_baseline = pd.DataFrame({
    'timestamp': df_clean['timestamp'],
    'sensor_id': df_clean['sensor_id'],
    'power_output': baseline_power
})
df_baseline.to_csv('/home/user/baseline_predictions.csv', index=False)
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
