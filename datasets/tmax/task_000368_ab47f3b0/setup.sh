#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)

with open("/home/user/sensor_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "temperature", "pressure"])

    for i in range(1000):
        # Generate base correlation
        temp = random.gauss(20, 5)
        # Pressure is loosely correlated with temperature
        pressure = 1013 + (temp - 20) * 2 + random.gauss(0, 10)

        # Inject bad data roughly 10% of the time
        rand_val = random.random()
        if rand_val < 0.03:
            writer.writerow([f"2023-01-01T12:00:{i:02d}Z", "NaN", pressure])
        elif rand_val < 0.06:
            writer.writerow([f"2023-01-01T12:00:{i:02d}Z", temp, "error"])
        elif rand_val < 0.08:
            writer.writerow([f"2023-01-01T12:00:{i:02d}Z", 100.5, pressure]) # invalid temp
        elif rand_val < 0.10:
            writer.writerow([f"2023-01-01T12:00:{i:02d}Z", temp, 800.0]) # invalid pressure
        else:
            writer.writerow([f"2023-01-01T12:00:{i:02d}Z", round(temp, 4), round(pressure, 4)])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
