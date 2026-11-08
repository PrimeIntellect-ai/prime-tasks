#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
sensor_a = np.random.normal(10, 2, n)
sensor_b = sensor_a * 1.5 + np.random.normal(0, 1, n)

# Missing values
sensor_a[np.random.choice(n, 50, replace=False)] = np.nan
sensor_b[np.random.choice(n, 50, replace=False)] = np.nan

group = np.random.choice(['control', 'treatment'], n)
value_c = np.where(group == 'treatment', np.random.normal(5, 1, n), np.random.normal(4.5, 1, n))
value_c[np.random.choice(n, 100, replace=False)] = np.nan

df = pd.DataFrame({
    'timestamp': pd.date_range(start='2023-01-01', periods=n, freq='H'),
    'sensor_a': sensor_a,
    'sensor_b': sensor_b,
    'group': group,
    'value_c': value_c
})
df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
