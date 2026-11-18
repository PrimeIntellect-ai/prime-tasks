#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/process_data.py
import pandas as pd
import numpy as np

def process_and_compute():
    # Load data
    df = pd.read_csv('/home/user/sensor_data.csv')

    # Clean data: replace missing value placeholders and convert to float
    df = df.replace('MISSING', np.nan)
    df = df.astype(float)

    # Drop rows with missing timestamps
    df = df.dropna(subset=['timestamp_ns'])

    # Aggregate duplicate timestamps by taking the mean of the sensors
    df_grouped = df.groupby('timestamp_ns').mean()

    # Compute the covariance matrix of the aggregated sensors
    cov_matrix = df_grouped[['sensor_A', 'sensor_B', 'sensor_C']].cov()

    # Calculate the sum of all elements in the covariance matrix
    cov_sum = cov_matrix.to_numpy().sum()

    with open('/home/user/cov_sum.txt', 'w') as f:
        f.write(f"{cov_sum:.4f}\n")

if __name__ == "__main__":
    process_and_compute()
EOF

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_rows = 50000

# Generate base timestamps around a large epoch
base_ts = 1680000000000000000
# Generate timestamps, with some duplicates to test groupby
timestamps = base_ts + np.random.randint(0, 10000, size=n_rows)

sensor_A = np.random.randn(n_rows) * 10
sensor_B = sensor_A * 0.5 + np.random.randn(n_rows) * 2
sensor_C = sensor_B * -1.2 + np.random.randn(n_rows) * 5

df = pd.DataFrame({
    'timestamp_ns': timestamps,
    'sensor_A': sensor_A,
    'sensor_B': sensor_B,
    'sensor_C': sensor_C
})

# Inject 'MISSING' into timestamps
missing_ts_idx = np.random.choice(n_rows, size=500, replace=False)
df.loc[missing_ts_idx, 'timestamp_ns'] = 'MISSING'

# Inject 'MISSING' into sensors
missing_A_idx = np.random.choice(n_rows, size=1000, replace=False)
df.loc[missing_A_idx, 'sensor_A'] = 'MISSING'

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
