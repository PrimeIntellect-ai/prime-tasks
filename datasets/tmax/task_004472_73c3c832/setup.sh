#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

np.random.seed(10)
n_samples = 200

data = {
    'temp': np.random.normal(10, 30, n_samples),
    'pressure': np.random.normal(1013, 50, n_samples),
    'humidity': np.random.normal(50, 30, n_samples),
}
# Create target with some linear relationship + noise
data['error_margin'] = 0.5 * data['temp'] - 0.1 * data['pressure'] + 0.2 * data['humidity'] + np.random.normal(0, 5, n_samples)
df = pd.DataFrame(data)

# Introduce schema violations
df.loc[5, 'temp'] = 100.0
df.loc[10, 'humidity'] = -10.0
df.loc[15, 'pressure'] = -5.0
df.loc[20, 'temp'] = np.nan

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
