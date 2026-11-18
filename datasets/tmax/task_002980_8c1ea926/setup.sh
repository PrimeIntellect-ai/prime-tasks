#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(101)

# Generate baseline data
n_samples = 200
machine_ids = np.random.choice(['M-101', 'M-102'], size=n_samples)

# True mean for M-101 is 55.0, for M-102 is 60.0
temps = np.where(machine_ids == 'M-101', 
                 np.random.normal(55.0, 2.0, n_samples),
                 np.random.normal(60.0, 3.0, n_samples))

# Introduce missing values
missing_idx = np.random.choice(n_samples, size=15, replace=False)
temps[missing_idx] = np.nan

# Introduce extreme outliers (e.g. sensor glitches)
outlier_idx = np.random.choice(n_samples, size=10, replace=False)
temps[outlier_idx] = temps[outlier_idx] + np.random.choice([-40, 40, 50, -50], size=10)

df = pd.DataFrame({
    'timestamp': pd.date_range(start='2023-01-01', periods=n_samples, freq='min'),
    'machine_id': machine_ids,
    'temperature': temps
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
