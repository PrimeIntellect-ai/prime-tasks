#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np
import json

# metadata
metadata = [
    {"device_id": "D1", "site": "North", "alert_threshold": 50.0},
    {"device_id": "D2", "site": "North", "alert_threshold": 55.0},
    {"device_id": "D3", "site": "South", "alert_threshold": 40.0}
]
with open("/home/user/raw_data/metadata.json", "w") as f:
    json.dump(metadata, f)

# telemetry
data = [
    # North site, temp
    ["2023-10-01 10:05:00", "D1", "temp", 45.0],
    ["10/01/2023 10:15", "D1", "temp", np.nan],
    ["2023-10-01 10:25:00", "D1", "temp", 55.0], # alert
    ["2023-10-01 10:25:00", "D1", "temp", 55.0], # duplicate
    # North site, humidity
    ["2023-10-01 10:10:00", "D2", "humidity", 60.0], # alert
    ["10/01/2023 10:20", "D2", "humidity", np.nan],
    ["2023-10-01 10:30:00", "D2", "humidity", np.nan],
    # South site, temp
    ["2023-10-01 11:05:00", "D3", "temp", 41.0], # alert
    ["2023-10-01 11:15:00", "D3", "temp", 39.0],
    # Ghost device
    ["2023-10-01 10:00:00", "D9", "temp", 100.0]
]

df = pd.DataFrame(data, columns=["timestamp", "device_id", "sensor_type", "value"])
df = df.sample(frac=1, random_state=42).reset_index(drop=True) # Shuffle
df.to_csv("/home/user/raw_data/telemetry.csv", index=False)
EOF

    python3 /home/user/setup_data.py

    chmod -R 777 /home/user
