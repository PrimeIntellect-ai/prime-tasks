#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import csv
import random

random.seed(42)
true_temp = 20.0
time_steps = 100

with open('/home/user/raw_sensor.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Time', 'Measurement'])
    for t in range(time_steps):
        # random walk for true temp
        true_temp += random.gauss(0, 0.2)
        # noisy measurement
        measurement = true_temp + random.gauss(0, 1.5)
        writer.writerow([f"{t:.1f}", f"{measurement:.4f}"])
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
