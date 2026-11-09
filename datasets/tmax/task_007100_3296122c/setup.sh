#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(123)
n_rows = 5000

ids = np.arange(n_rows)
# Introduce negative ids
ids[np.random.choice(n_rows, 50, replace=False)] = -1

sensor_A = np.random.normal(10, 2, n_rows).astype(str)
sensor_B = np.random.normal(5, 1.5, n_rows).astype(str)
sensor_C = np.random.normal(-2, 3, n_rows).astype(str)
status = np.random.choice([0, 1], n_rows)

# Introduce schema violations
err_idx = np.random.choice(n_rows, 100, replace=False)
sensor_A[err_idx] = "ERR"
sensor_B[np.random.choice(n_rows, 80, replace=False)] = "NaN_val"
status[np.random.choice(n_rows, 60, replace=False)] = 2

df = pd.DataFrame({
    'id': ids,
    'sensor_A': sensor_A,
    'sensor_B': sensor_B,
    'sensor_C': sensor_C,
    'status': status
})

# Add some true missing values
df.loc[np.random.choice(n_rows, 40, replace=False), 'sensor_C'] = np.nan

df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
