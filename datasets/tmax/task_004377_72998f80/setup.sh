#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

# Set up the initial data
dates = pd.date_range("2023-01-01 00:00:00", "2023-01-01 10:00:00", freq="1H")
df = pd.DataFrame({
    "timestamp": dates,
    "room_A": [20.1, 20.2, 20.1, 20.5, 20.6, 20.5, 20.4, 20.3, 20.2, 20.1, 20.0],
    "room_B": [22.1, 22.2, 22.1, 22.5, np.nan, 22.5, 22.4, 22.3, 22.2, 22.1, 22.0],
    "room_C": [19.1, 19.2, 19.1, 19.5, 19.6, 19.5, 19.4, 19.3, 19.2, 19.1, 19.0]
})

# Drop some rows to create gaps (drop 03:00:00 and 07:00:00)
df = df.drop([3, 7])

# Add duplicates
df = pd.concat([df, df.iloc[1:3], df.iloc[5:6]]).sort_values("timestamp")

# Save raw
df.to_csv("/home/user/raw_sensors.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
