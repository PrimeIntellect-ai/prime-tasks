#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 1000

# Generate timestamps
timestamps = pd.date_range(start="2023-01-01", periods=n_samples, freq="1H")

# Sensor A
sensor_A = np.linspace(10, 50, n_samples) + np.random.normal(0, 1, n_samples)

# Sensor B (highly correlated with A)
sensor_B = 3.5 * sensor_A - 12.0 + np.random.normal(0, 2, n_samples)

# Sensor C (independent, with a slight shift in the second half)
sensor_C = np.concatenate([
    np.random.normal(100, 15, 500),
    np.random.normal(102, 15, 500)
])

# Introduce anomalies in B
anomaly_indices = np.random.choice(n_samples, 20, replace=False)
sensor_B[anomaly_indices] += np.random.choice([15.0, -15.0, 20.0, -20.0], 20)

# Introduce missing values
nan_indices_A = np.random.choice(n_samples, 10, replace=False)
nan_indices_B = np.random.choice(n_samples, 15, replace=False)
nan_indices_C = np.random.choice(n_samples, 12, replace=False)

# Make sure first and last aren't nan for clean interpolation
for idx in [0, n_samples-1]:
    if idx in nan_indices_A: nan_indices_A = np.delete(nan_indices_A, np.where(nan_indices_A == idx))
    if idx in nan_indices_B: nan_indices_B = np.delete(nan_indices_B, np.where(nan_indices_B == idx))
    if idx in nan_indices_C: nan_indices_C = np.delete(nan_indices_C, np.where(nan_indices_C == idx))

sensor_A[nan_indices_A] = np.nan
sensor_B[nan_indices_B] = np.nan
sensor_C[nan_indices_C] = np.nan

df = pd.DataFrame({
    'timestamp': timestamps,
    'sensor_A': sensor_A,
    'sensor_B': sensor_B,
    'sensor_C': sensor_C
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
