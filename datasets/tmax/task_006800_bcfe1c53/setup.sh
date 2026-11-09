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
n_rows = 1000

# Normal readings
sensor_A = np.random.normal(0, 10, n_rows)
# Sensor B is highly correlated with A
sensor_B = sensor_A + np.random.normal(0, 1, n_rows)
# Sensor C has normal readings + some anomalies + some out of bounds
sensor_C = np.random.normal(0, 10, n_rows)
# Inject anomalies (in bounds but unlikely under normal)
sensor_C[10:30] = np.random.uniform(40, 90, 20)
# Inject out of bounds
sensor_C[50:60] = np.random.uniform(150, 200, 10)
# Sensor D is completely normal
sensor_D = np.random.normal(0, 10, n_rows)

df = pd.DataFrame({
    'sensor_A': sensor_A,
    'sensor_B': sensor_B,
    'sensor_C': sensor_C,
    'sensor_D': sensor_D
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
