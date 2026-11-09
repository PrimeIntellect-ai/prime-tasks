#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import random
from datetime import datetime, timedelta

os.makedirs('/home/user', exist_ok=True)

# Generate sensors.csv
sensors = []
sensor_types = ['temperature', 'humidity', 'pressure']
locations = ['loc_alpha', 'loc_beta', 'loc_gamma']

with open('/home/user/sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['sensor_id', 'sensor_type', 'location_id'])
    for i in range(1, 101):
        s_type = random.choice(sensor_types)
        loc = random.choice(locations)
        sensors.append(i)
        writer.writerow([i, s_type, loc])

# Generate readings.csv
start_time = datetime(2023, 1, 1)
with open('/home/user/readings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['reading_id', 'sensor_id', 'reading_value', 'timestamp'])
    r_id = 1
    for s_id in sensors:
        # Each sensor gets 50 readings
        for j in range(50):
            val = round(random.uniform(10.0, 100.0), 2)
            ts = (start_time + timedelta(minutes=j*15)).isoformat()
            writer.writerow([r_id, s_id, val, ts])
            r_id += 1
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
