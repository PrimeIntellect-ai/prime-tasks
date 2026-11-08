#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random
import os

os.makedirs('/home/user', exist_ok=True)
output_file = '/home/user/sensor_data.csv'

# Deterministic generation
random.seed(42)

with open(output_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_id', 'voltage', 'current'])

    for i in range(10000):
        # 1% chance of invalid (negative voltage)
        if random.random() < 0.01:
            writer.writerow([f'2023-10-01T12:00:{i%60:02d}Z', f'S-{i%10}', -5.0, 10.0])
        # 1% chance of invalid (missing sensor_id)
        elif random.random() < 0.01:
            writer.writerow([f'2023-10-01T12:00:{i%60:02d}Z', '', 120.0, 10.0])
        # 2% chance of anomaly (power > 5000)
        elif random.random() < 0.02:
            writer.writerow([f'2023-10-01T12:00:{i%60:02d}Z', f'S-{i%10}', 240.0, 25.0]) # power = 6000
        # Normal
        else:
            writer.writerow([f'2023-10-01T12:00:{i%60:02d}Z', f'S-{i%10}', 120.0, 15.0]) # power = 1800
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    mkdir -p /home/user/etl_pipeline

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
