#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random

random.seed(42)

machines = ['M_01', 'M_02', 'M_03']
data = []
timestamp = 1600000000

for i in range(100):
    for m in machines:
        timestamp += 1
        # Normal reading
        val = random.gauss(10.0, 1.0)

        # Inject anomalies
        if i == 25 and m == 'M_02':
            val = 20.0
        if i == 70 and m == 'M_01':
            val = 2.0

        data.append((timestamp, m, val))

data.sort(key=lambda x: x[0])

with open('/home/user/vibration_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Timestamp', 'MachineID', 'VibrationValue'])
    for row in data:
        writer.writerow([row[0], row[1], f"{row[2]:.4f}"])
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
