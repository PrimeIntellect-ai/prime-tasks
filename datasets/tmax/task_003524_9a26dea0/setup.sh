#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/remote_inbox
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

# Sensor Alpha (UTF-8, ISO8601)
alpha_data = pd.DataFrame({
    'sensor_id': ['alpha']*6,
    'timestamp': ['2023-10-01T10:00:00Z', '2023-10-01T10:05:00Z', '2023-10-01T10:05:00Z', '2023-10-01T10:10:00Z', '2023-10-01T10:15:00Z', '2023-10-01T10:15:00Z'],
    'temperature': [20.0, 21.5, 21.5, 22.0, 21.0, 21.0] # 10:05 and 10:15 are duplicated
})
alpha_data.to_csv('/home/user/remote_inbox/sensor_alpha.csv', index=False, encoding='utf-8')

# Sensor Beta (UTF-16, Epoch)
beta_data = pd.DataFrame({
    'sensor_id': ['beta']*5,
    'timestamp': [1696154400, 1696154700, 1696155000, 1696154400, 1696155300], # Duplicated 1696154400 out of order
    'temperature': [15.0, 16.0, 15.5, 15.0, 17.0]
})
beta_data.to_csv('/home/user/remote_inbox/sensor_beta.csv', index=False, encoding='utf-16')

# Sensor Gamma (Latin1, DD-MM-YYYY HH:MM:SS)
gamma_data = pd.DataFrame({
    'sensor_id': ['gamma']*4,
    'timestamp': ['01-10-2023 10:00:00', '01-10-2023 10:05:00', '01-10-2023 10:10:00', '01-10-2023 10:05:00'],
    'temperature': [30.0, 31.0, 30.5, 31.0]
})
gamma_data.to_csv('/home/user/remote_inbox/sensor_gamma.csv', index=False, encoding='iso-8859-1')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    cat << 'EOF' > /home/user/verify.py
import pandas as pd
import sys

def verify():
    output_file = '/home/user/output/clean_aggregates.csv'
    try:
        df = pd.read_csv(output_file)
    except FileNotFoundError:
        print("Verification failed: Output file not found.")
        sys.exit(1)

    required_cols = ['sensor_id', 'timestamp_utc', 'temp_rolling_avg']
    if list(df.columns) != required_cols:
        print(f"Verification failed: Incorrect columns. Expected {required_cols}")
        sys.exit(1)

    if len(df) != 11:
        print(f"Verification failed: Expected 11 records, got {len(df)}")
        sys.exit(1)

    # Check specific values for validation
    alpha_10_10 = df[(df['sensor_id'] == 'alpha') & (df['timestamp_utc'] == '2023-10-01 10:10:00')]['temp_rolling_avg'].values[0]
    if not (21.16 <= alpha_10_10 <= 21.18):
        print(f"Verification failed: Expected alpha rolling avg ~21.17, got {alpha_10_10}")
        sys.exit(1)

    beta_10_15 = df[(df['sensor_id'] == 'beta') & (df['timestamp_utc'] == '2023-10-01 10:15:00')]['temp_rolling_avg'].values[0]
    if not (16.16 <= beta_10_15 <= 16.18):
        print(f"Verification failed: Expected beta rolling avg ~16.17, got {beta_10_15}")
        sys.exit(1)

    print("Verification passed.")
    sys.exit(0)

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
