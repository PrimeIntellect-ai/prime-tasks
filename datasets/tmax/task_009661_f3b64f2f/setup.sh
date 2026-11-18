#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional requirements
    pip3 install pandas numpy
    apt-get install -y r-base r-cran-jsonlite

    # Create data directory and setup data
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(123)
timestamps = pd.date_range('2023-01-01', periods=500, freq='D')
true_signal = np.sin(np.linspace(0, 10, 500)) * 5
target = true_signal + np.random.normal(0, 1, 500)

sensor_a = true_signal + np.random.normal(0, np.sqrt(2.0), 500)
sensor_b = true_signal + np.random.normal(0, np.sqrt(4.0), 500)
sensor_c = true_signal + np.random.normal(0, np.sqrt(1.0), 500)

idx_a = np.random.choice(500, 400, replace=False)
idx_b = np.random.choice(500, 450, replace=False)
idx_c = np.random.choice(500, 480, replace=False)

pd.DataFrame({'timestamp': timestamps[idx_a], 'value_a': sensor_a[idx_a]}).to_csv('/home/user/data/sensor_a.csv', index=False)
pd.DataFrame({'timestamp': timestamps[idx_b], 'value_b': sensor_b[idx_b]}).to_csv('/home/user/data/sensor_b.csv', index=False)
pd.DataFrame({'timestamp': timestamps[idx_c], 'value_c': sensor_c[idx_c]}).to_csv('/home/user/data/sensor_c.csv', index=False)
pd.DataFrame({'timestamp': timestamps, 'target': target}).to_csv('/home/user/data/target.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
