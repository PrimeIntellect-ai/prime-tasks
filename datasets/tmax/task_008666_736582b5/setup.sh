#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import json
import random

os.makedirs('/home/user/data', exist_ok=True)

random.seed(42)

with open('/home/user/data/sensor_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_id', 'metadata_json', 'raw_value'])

    for i in range(10000):
        timestamp = f"2023-10-01T{i%24:02d}:00:00Z"

        # Introduce the typo
        if random.random() < 0.3:
            sensor_id = f"sensro_{random.randint(10, 99)}"
        else:
            sensor_id = f"sensor_{random.randint(10, 99)}"

        offset = round(random.uniform(-5.0, 5.0), 2)
        multiplier = round(random.uniform(0.8, 1.5), 2)
        status = random.choice(["active", "active", "active", "maintenance", "offline"])

        metadata = {
            "calibration": {"offset": offset, "multiplier": multiplier},
            "status": status
        }

        raw_value = round(random.uniform(10.0, 100.0), 2)

        writer.writerow([timestamp, sensor_id, json.dumps(metadata), raw_value])
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
