#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
dates = pd.date_range('2023-01-01', '2023-01-02', freq='1h')
sensors = ['S1', 'S2']

data = []
for d in dates:
    for s in sensors:
        temp = np.random.normal(20, 5)
        hum = np.random.normal(50, 10)
        data.append([d, s, temp, hum])

df = pd.DataFrame(data, columns=['timestamp', 'sensor_id', 'temperature_c', 'humidity'])

# Inject dirty data
df.loc[5, 'timestamp'] = np.nan
df.loc[10, 'temperature_c'] = 999.9  # Outlier > 80
df.loc[15, 'temperature_c'] = -40.5  # Outlier < -30
df.loc[22, 'temperature_c'] = np.nan # Missing
df.loc[20, 'humidity'] = np.nan      # Missing
df.loc[31, 'humidity'] = np.nan      # Missing

df.to_csv('/home/user/raw_sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
