#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import random
import csv

random.seed(42)

data = []
data.append(["timestamp", "sensor_id", "temperature", "humidity"])

# Good data for sensor 1
for i in range(20):
    data.append([f"2023-01-01T12:{i:02d}:00Z", 1, round(random.gauss(22, 2), 2), 45.0])

# Good data for sensor 2
for i in range(20):
    data.append([f"2023-01-01T12:{i:02d}:00Z", 2, round(random.gauss(15, 2), 2), 55.0])

# Schema errors
data.append(["2023-01-01T12:20:00Z", 1, "invalid_float", 45.0]) # Type error
data.append(["2023-01-01T12:21:00Z", 2, 20.0, 105.0]) # Out of bounds humidity
data.append(["2023-01-01T12:22:00Z", 3, -60.0, 50.0]) # Out of bounds temp
data.append(["2023-01-01T12:23:00Z", "sensor_four", 20.0, 50.0]) # Type error sensor_id

# Bayesian Anomalies
# Sensor 1: mu_post will be ~22. Predict stdev ~2.0. So 3*2 = 6. Let's add a reading of 30.
data.append(["2023-01-01T13:00:00Z", 1, 35.0, 45.0]) # Anomaly!

# Sensor 2: mu_post will be ~15. Predict stdev ~2.0. Let's add a reading of 5.
data.append(["2023-01-01T13:01:00Z", 2, 5.0, 55.0]) # Anomaly!

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/raw_sensor_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
