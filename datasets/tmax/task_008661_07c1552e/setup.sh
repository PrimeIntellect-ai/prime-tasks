#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_csv.py
import csv
import random

random.seed(42)

with open("/home/user/raw_sensor_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "sensor_id", "temperature", "humidity"])
    for i in range(1000):
        # Introduce NaNs
        if i % 50 == 0:
            writer.writerow([f"2023-10-01T{i:04d}", "A", "", "45.0"])
            continue

        sensor = random.choice(["A", "B", "C"])
        temp = random.gauss(20, 5)
        hum = random.gauss(50, 10)

        # Introduce Outliers
        if i == 10: temp = 1000.0
        if i == 20: temp = -1000.0
        if i == 30: hum = 1000.0
        if i == 40: hum = -1000.0

        writer.writerow([f"2023-10-01T{i:04d}", sensor, round(temp, 2), round(hum, 2)])
EOF

    python3 /tmp/generate_csv.py
    rm /tmp/generate_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
