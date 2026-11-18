#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

# Generate valid data
n_samples = 200
mass_0 = np.random.normal(10, 2, n_samples // 2)
volume_0 = np.random.normal(5, 1, n_samples // 2)
class_0 = np.zeros(n_samples // 2)

mass_1 = np.random.normal(20, 3, n_samples // 2)
volume_1 = np.random.normal(15, 2, n_samples // 2)
class_1 = np.ones(n_samples // 2)

mass = np.concatenate([mass_0, mass_1])
volume = np.concatenate([volume_0, volume_1])
classes = np.concatenate([class_0, class_1])

df = pd.DataFrame({'mass': mass, 'volume': volume, 'class': classes})

# Shuffle dataset
df = df.sample(frac=1, random_state=42).reset_index(drop=True)

# Inject dirty data to test schema enforcement
dirty_rows = pd.DataFrame([
    {'mass': -1.5, 'volume': 5.0, 'class': 0}, # negative mass
    {'mass': 15.0, 'volume': 0.0, 'class': 1}, # zero volume
    {'mass': 12.0, 'volume': 8.0, 'class': 2}, # invalid class
    {'mass': np.nan, 'volume': 7.0, 'class': 0}, # missing value
    {'mass': 10.0, 'volume': -2.0, 'class': 1}, # negative volume
    {'mass': "error", 'volume': 10.0, 'class': 0} # string
])

df_dirty = pd.concat([df.iloc[:50], dirty_rows, df.iloc[50:]], ignore_index=True)
df_dirty.to_csv('/home/user/data/unorganized_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
