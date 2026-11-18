#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
from datetime import datetime, timedelta
import random

random.seed(42)
records = []
start_time = datetime(2024, 1, 1, 0, 0, 0)

# Generate a sequence of timestamps with some gaps
current_time = start_time
while current_time < datetime(2024, 1, 1, 1, 0, 0):
    # Add valid temperature sensors
    if random.random() < 0.7:
        name = random.choice(["TempSensor", "Temperatursensor", "温度計"])
        reading = round(random.uniform(20.0, 30.0), 2)
        # Avoid Apptainer build variables by not using double curly braces
        notes = "Log entry {OP-" + str(random.randint(100,999)) + "} generated."
        records.append((current_time.strftime("%Y-%m-%dT%H:%M:%SZ"), name, reading, notes))

    # Add invalid sensors
    if random.random() < 0.3:
        records.append((current_time.strftime("%Y-%m-%dT%H:%M:%SZ"), "Humidity", 45.0, "Normal {H-100}"))

    # Irregular jump: 10 to 120 seconds
    jump = random.randint(10, 120)
    current_time += timedelta(seconds=jump)

with open("/home/user/raw_sensor_logs.csv", "w", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "sensor_name", "reading", "notes"])
    for r in records:
        writer.writerow(r)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
