#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import math
import random

random.seed(42)
P0_true = 1015.0
H_true = 8000.0

with open('/home/user/raw_obs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'altitude_m', 'pressure_hpa', 'sensor_status'])

    for i in range(100):
        alt = random.uniform(-100, 10000)
        status = "OK" if random.random() > 0.1 else "FAIL"

        # Add some noise
        noise = random.normalvariate(0, 5.0)
        p = P0_true * math.exp(-alt / H_true) + noise
        if p <= 0:
            p = 0.1

        writer.writerow([i, round(alt, 2), round(p, 2), status])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
