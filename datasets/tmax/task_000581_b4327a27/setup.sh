#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)

def generate_data():
    records = []
    base_time = datetime(2023, 10, 1, 12, 0, 0)

    # Bucket 1: 12:00:00
    # Sensor A: 2 distinct points + 1 duplicate
    records.append((base_time + timedelta(seconds=10), 'sensor_A', 10.0, 20.0))
    records.append((base_time + timedelta(seconds=15), 'sensor_A', 10.05, 19.95)) # dist ~0.07 (duplicate)
    records.append((base_time + timedelta(seconds=45), 'sensor_A', 15.0, 25.0)) # distinct

    # Sensor B: 1 point + 2 duplicates
    records.append((base_time + timedelta(seconds=5), 'sensor_B', 5.0, 5.0))
    records.append((base_time + timedelta(seconds=6), 'sensor_B', 5.02, 5.02)) # dup
    records.append((base_time + timedelta(seconds=7), 'sensor_B', 5.08, 4.98)) # dup

    # Bucket 2: 12:01:00
    # Sensor A: 1 point
    records.append((base_time + timedelta(seconds=70), 'sensor_A', 11.0, 21.0))

    # Write to CSV
    with open('/home/user/raw_sensor_data.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'sensor_id', 'x', 'y'])
        for r in records:
            writer.writerow([r[0].strftime('%Y-%m-%dT%H:%M:%SZ'), r[1], r[2], r[3]])

generate_data()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
