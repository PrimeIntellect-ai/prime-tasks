#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import csv
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
timestamps = np.arange(0, 10000, 1) # 10 seconds of data, 1 sample per ms
# Base 50us latency + 0.0125us/ms linear drift + 60Hz periodic interference + Gaussian noise
latencies = 50 + 0.0125 * timestamps + 12 * np.sin(2 * np.pi * 60 * (timestamps / 1000.0)) + np.random.normal(0, 2, len(timestamps))

with open('/home/user/ui_latency.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp_ms', 'latency_us'])
    for t, l in zip(timestamps, latencies):
        writer.writerow([t, l])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
