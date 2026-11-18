#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgomp1
    pip3 install pytest

    mkdir -p /tmp/remote_data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/remote_data/generate.py
import csv

with open('/tmp/remote_data/sensor_readings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['DeviceID', 'T0', 'T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9'])

    for i in range(1, 10001):
        row = [i]
        for t in range(10):
            val = (i % 100) + t * 2.5
            row.append(round(val, 2))
        writer.writerow(row)
EOF

    python3 /tmp/remote_data/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /tmp/remote_data
