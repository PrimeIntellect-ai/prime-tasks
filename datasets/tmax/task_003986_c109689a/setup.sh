#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

# Create base timeline
np.random.seed(42)
times = pd.date_range("2023-10-01 10:00:00", "2023-10-01 12:00:00", freq="5min")

data = []
# Sensor A data
for t in times:
    if t.minute not in [15, 20]: # Create gaps
        data.append({'ts': t, 'sensor': 'sensor_A', 'temp': np.random.uniform(20.0, 25.0), 'etl_run': 1})

# Sensor B data starts late, ends early
for t in times[3:-3]:
    if t.minute not in [45, 50]: # Create gaps
        data.append({'ts': t, 'sensor': 'sensor_B', 'temp': np.random.uniform(15.0, 18.0), 'etl_run': 1})

df = pd.DataFrame(data)

# Introduce duplicates with higher etl_run
duplicates = df.sample(frac=0.3, random_state=42).copy()
duplicates['etl_run'] = 2
duplicates['temp'] = duplicates['temp'] + np.random.uniform(-1, 1, size=len(duplicates))

df = pd.concat([df, duplicates]).sample(frac=1, random_state=123).reset_index(drop=True)

df.to_csv("/home/user/raw_sensor_data.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
