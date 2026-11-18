#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 502

# sensor 1: normal + 2 outliers
sensor1 = np.random.normal(loc=10.0, scale=2.0, size=n_samples)
sensor1[50] = 50.0  # outlier 1
sensor1[200] = -40.0 # outlier 2

# sensor 2: normal + NaNs
sensor2 = np.random.normal(loc=5.0, scale=1.0, size=n_samples)
nan_indices = np.random.choice(n_samples, size=20, replace=False)
sensor2[nan_indices] = np.nan

# target: linear combination + noise
target = 3.0 + 1.5 * sensor1 + -2.0 * np.nan_to_num(sensor2, nan=5.0) + np.random.normal(0, 0.5, size=n_samples)

df = pd.DataFrame({
    'timestamp': pd.date_range(start='2023-01-01', periods=n_samples, freq='min'),
    'sensor1': sensor1,
    'sensor2': sensor2,
    'target': target
})

df.to_csv('/home/user/sensor_data.csv', index=False, na_rep='NaN')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
