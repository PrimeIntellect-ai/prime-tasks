#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import random
import math

os.makedirs('/home/user/raw_data', exist_ok=True)
os.makedirs('/home/user/reference', exist_ok=True)
os.makedirs('/home/user/clean_data', exist_ok=True)
os.makedirs('/home/user/metrics', exist_ok=True)

# Generate baseline
baseline = [10.0 + 5.0 * math.sin(i * math.pi / 12) for i in range(24)]
with open('/home/user/reference/baseline.json', 'w') as f:
    json.dump(baseline, f)

# Generate raw data with duplicates
sensors = ['sensor_A', 'sensor_B', 'sensor_C']
rows = []
for s in sensors:
    for i in range(24):
        ts = f"2023-10-01T{i:02d}:00:00Z"
        if s == 'sensor_A':
            val = baseline[i] + 0.5
        elif s == 'sensor_B':
            val = baseline[i] + (i % 3)
        else:
            val = baseline[i] - 2.0

        row = f"{ts},{s},{val:.3f}\n"
        rows.append(row)

        if random.random() < 0.3:
            rows.append(row)

random.seed(42)
random.shuffle(rows)

with open('/home/user/raw_data/sensors_20231001.csv', 'w') as f:
    f.write("timestamp,sensor_id,value\n")
    f.writelines(rows)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
