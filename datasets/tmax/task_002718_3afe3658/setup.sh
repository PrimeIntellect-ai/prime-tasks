#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
n_samples = 200

timestamps = pd.date_range("2023-01-01", periods=n_samples, freq="H")

# Create base sensors
sensor_A = np.cumsum(np.random.randn(n_samples))
sensor_B = np.random.randn(n_samples) * 5
sensor_C = sensor_B + np.random.randn(n_samples) * 0.5  # Highly correlated with B
sensor_D = np.random.uniform(0, 10, n_samples)
sensor_E = np.sin(np.linspace(0, 10, n_samples))

df_sensors = pd.DataFrame({
    'timestamp': timestamps,
    'sensor_A': sensor_A,
    'sensor_B': sensor_B,
    'sensor_C': sensor_C,
    'sensor_D': sensor_D,
    'sensor_E': sensor_E
})

# Create target
target = 2.0 * sensor_A - 0.5 * sensor_B + 1.5 * sensor_D + np.random.randn(n_samples)

df_target = pd.DataFrame({
    'timestamp': timestamps,
    'target_value': target
})

# Scramble rows slightly to test sorting/merging
df_sensors = df_sensors.sample(frac=1.0, random_state=1).reset_index(drop=True)
df_target = df_target.sample(frac=1.0, random_state=2).reset_index(drop=True)

df_sensors.to_csv('/home/user/sensor_readings.csv', index=False)
df_target.to_csv('/home/user/target_values.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
