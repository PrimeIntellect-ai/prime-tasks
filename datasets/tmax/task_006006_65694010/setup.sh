#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import random
import csv

os.makedirs('/home/user', exist_ok=True)

random.seed(123)
total_rows = 2000

with open('/home/user/inference_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'temp_feature', 'pressure_feature', 'actual_state', 'predicted_state'])

    for i in range(total_rows):
        timestamp = 1680000000 + i
        temp = random.randint(0, 100)
        pressure = random.randint(0, 100)

        pred = 1 if pressure > 73 else 0

        if random.random() < 0.08:
            actual = 1 - pred
        else:
            actual = pred

        writer.writerow([timestamp, temp, pressure, actual, pred])
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
