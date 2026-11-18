#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import random

os.makedirs('/home/user/data', exist_ok=True)

random.seed(42)
with open('/home/user/data/raw_sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'sensor_1', 'sensor_2', 'target'])

    for i in range(1, 1001):
        s1 = random.uniform(-2.0, 10.0)
        s2 = random.uniform(-2.0, 10.0)

        if s1 < 0 or s2 < 0:
            target = 0.0
        else:
            s3 = s1 * s2
            target = 2.5 + 1.5 * s1 + (-0.8) * s2 + 0.4 * s3

        writer.writerow([i, s1, s2, target])
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
