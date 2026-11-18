#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import pandas as pd
import numpy as np

# Set random seed for reproducibility
np.random.seed(42)

# Generate baseline data
n_samples = 100
data = {
    'sensor_A': np.random.normal(10, 2, n_samples),
    'sensor_B': np.random.normal(50, 10, n_samples),
    'sensor_D': np.random.normal(0, 1, n_samples),
    'sensor_E': np.random.normal(-10, 5, n_samples)
}

# Create sensor_C which is highly correlated with sensor_A
data['sensor_C'] = data['sensor_A'] * 3.5 + np.random.normal(0, 0.5, n_samples)

df = pd.DataFrame(data)

# Reorder columns
df = df[['sensor_A', 'sensor_B', 'sensor_C', 'sensor_D', 'sensor_E']]

# Inject missing values
df.loc[5, 'sensor_B'] = np.nan
df.loc[6, 'sensor_B'] = np.nan
df.loc[0, 'sensor_A'] = np.nan # requires backfill after forward fill

# Inject outliers (Z > 3.0)
# sensor_D mean is ~0, std is ~1. A value of 5.5 will have Z > 3
df.loc[15, 'sensor_D'] = 5.5
# sensor_E mean is ~-10, std is ~5. A value of -35 will have Z > 3
df.loc[42, 'sensor_E'] = -35.0
# sensor_B mean is ~50, std is ~10. A value of 95 will have Z > 3
df.loc[88, 'sensor_B'] = 95.0

# Save to CSV
os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
