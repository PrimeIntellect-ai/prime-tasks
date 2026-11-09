#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    # Generate initial telemetry data
    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

data = [
    # device 1
    ["2023-10-01T10:01:00Z", "DEV1", 45.0, 4000, 25.0],
    ["2023-10-01T10:02:00Z", "DEV1", 50.0, 3950, 25.5],
    ["2023-10-01T10:02:00Z", "DEV1", 50.0, 3950, 25.5], # duplicate
    ["2023-10-01T10:05:00Z", "DEV1", 40.0, 3900, 26.0],
    ["2023-10-01T10:06:00Z", "DEV1", -10.0, 3900, 26.0], # invalid
    ["2023-10-01T10:16:00Z", "DEV1", 60.0, 3800, 27.0],
    ["2023-10-01T10:18:00Z", "DEV1", 55.0, 3700, 28.0],
    # device 2
    ["2023-10-01T10:14:00Z", "DEV2", 30.0, 4250, 22.0], # battery > 4200 -> cap to 100%
    ["2023-10-01T10:20:00Z", "DEV2", 35.0, np.nan, 23.0], # missing battery
    ["2023-10-01T10:22:00Z", "DEV2", 32.0, 3100, 23.5], # battery < 3200 -> cap to 0%
    ["2023-10-01T10:25:00Z", "DEV2", 38.0, 3250, 24.0]
]

os.makedirs('/home/user', exist_ok=True)
df = pd.DataFrame(data, columns=['timestamp', 'device_id', 'speed_kmh', 'battery_mv', 'temp_c'])
df.to_csv('/home/user/telemetry_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
