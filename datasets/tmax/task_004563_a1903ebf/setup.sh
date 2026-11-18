#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(123)
dates = pd.date_range(start='2023-01-01 00:00:00', periods=24*60*5, freq='min')

devices = ['Device_A', 'Device_B', 'Device_C', 'Device_D', 'Device_E']
data = []

t = np.linspace(0, 50, len(dates))
base_signal = np.sin(t)

for device in devices:
    if device == 'Device_A':
        values = base_signal
    elif device == 'Device_B':
        values = base_signal + np.random.normal(0, 0.1, len(dates))
    elif device == 'Device_C':
        values = base_signal + np.random.normal(0, 0.5, len(dates))
    elif device == 'Device_D':
        values = np.cos(t)
    elif device == 'Device_E':
        values = np.random.normal(0, 1, len(dates))

    df = pd.DataFrame({
        'timestamp': dates,
        'device_id': device,
        'value': values
    })
    data.append(df)

full_df = pd.concat(data)
full_df = full_df.sample(frac=1, random_state=99).reset_index(drop=True)
full_df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
