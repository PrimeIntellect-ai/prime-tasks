#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

# Create deterministic data
np.random.seed(42)
timestamps = pd.date_range("2023-01-01", periods=1000, freq="h")
sensor_A = np.sin(np.linspace(0, 20, 1000)) + np.random.normal(0, 0.1, 1000)
sensor_B = np.cos(np.linspace(0, 20, 1000)) + np.random.normal(0, 0.1, 1000)

# Inject missing values
sensor_A[::25] = np.nan

# Inject extreme outliers
sensor_B[100] = 5000.0
sensor_B[250] = -3000.0
sensor_B[800] = 10000.0

df = pd.DataFrame({
    "timestamp": timestamps,
    "sensor_A": sensor_A,
    "sensor_B": sensor_B
})

df.to_csv("/home/user/sensor_data.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
