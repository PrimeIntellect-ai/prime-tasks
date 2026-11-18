#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /tmp/setup_data.py
import os
import csv

os.makedirs('/home/user/sensor_data', exist_ok=True)

sensor_a_data = [
    ('2023-10-01T00:00:00Z', 'sensor_A', 20.0),
    ('2023-10-01T01:00:00Z', 'sensor_A', 21.0),
    ('2023-10-01T02:00:00Z', 'sensor_A', 19.0),
    ('2023-10-01T03:00:00Z', 'sensor_A', 20.0),
    ('2023-10-01T04:00:00Z', 'sensor_A', 22.0),
    ('2023-10-01T05:00:00Z', 'sensor_A', 18.0),
    ('2023-10-01T06:00:00Z', 'sensor_A', 20.0),
    ('2023-10-01T07:00:00Z', 'sensor_A', 21.0),
    ('2023-10-01T08:00:00Z', 'sensor_A', 19.0),
    ('2023-10-01T09:00:00Z', 'sensor_A', 50.0),
]

sensor_b_data = [
    ('2023-10-01T00:00:00Z', 'sensor_B', 40.0),
    ('2023-10-01T01:00:00Z', 'sensor_B', 41.0),
    ('2023-10-01T02:00:00Z', 'sensor_B', 39.0),
    ('2023-10-01T03:00:00Z', 'sensor_B', 40.0),
    ('2023-10-01T04:00:00Z', 'sensor_B', 42.0),
    ('2023-10-01T05:00:00Z', 'sensor_B', 38.0),
    ('2023-10-01T06:00:00Z', 'sensor_B', 40.0),
    ('2023-10-01T07:00:00Z', 'sensor_B', 41.0),
    ('2023-10-01T08:00:00Z', 'sensor_B', 39.0),
    ('2023-10-01T09:00:00Z', 'sensor_B', 10.0),
]

with open('/home/user/sensor_data/sensor_A.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_id', 'temperature'])
    writer.writerows(sensor_a_data)

with open('/home/user/sensor_data/sensor_B.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_id', 'temperature'])
    writer.writerows(sensor_b_data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
