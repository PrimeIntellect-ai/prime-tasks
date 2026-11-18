#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random

random.seed(42)
n = 1000
with open('/home/user/data/sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'temperature', 'pressure'])
    for i in range(1, n + 1):
        temp = random.uniform(20.0, 80.0)
        noise = random.gauss(0, 2.0)
        pressure = 2.5 * temp + 10.0 + noise
        writer.writerow([i, round(temp, 4), round(pressure, 4)])
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
