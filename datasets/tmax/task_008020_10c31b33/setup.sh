#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_csv.py
import random
import csv

random.seed(42)
with open('/home/user/sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for i in range(10000):
        ts = 1600000000 + i * 10
        sensor = f"SENS_{random.randint(1, 10):02d}"
        temp = round(random.uniform(20.0, 100.0), 2)
        hum = round(random.uniform(30.0, 90.0), 2)
        status = random.choice(['OK', 'OK', 'OK', 'WARNING', 'ERROR'])
        writer.writerow([ts, sensor, temp, hum, status])
EOF

    python3 /home/user/generate_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
