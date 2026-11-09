#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np
import pandas as pd

np.random.seed(123)
n_samples = 1000

# Generate features
y_true = np.random.binomial(1, 0.5, n_samples)
sensor_1 = np.where(y_true == 1, np.random.normal(1.5, 1.0, n_samples), np.random.normal(-0.5, 1.0, n_samples))
sensor_2 = np.where(y_true == 1, np.random.normal(-1.0, 1.5, n_samples), np.random.normal(1.0, 1.5, n_samples))
sensor_3 = np.random.normal(0, 2.0, n_samples) # noise

df = pd.DataFrame({
    'sensor_1': sensor_1,
    'sensor_2': sensor_2,
    'sensor_3': sensor_3,
    'target': y_true
})

# Drop some targets to create unlabeled data
missing_idx = np.random.choice(n_samples, size=int(n_samples * 0.3), replace=False)
df.loc[missing_idx, 'target'] = np.nan

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
