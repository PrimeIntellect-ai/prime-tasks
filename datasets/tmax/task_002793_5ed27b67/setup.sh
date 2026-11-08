#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)

start_time = datetime(2023, 1, 1, 0, 0, 0)
roles = ['web', 'db', 'cache']

with open('/home/user/dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'server_role', 'cpu_usage', 'memory_usage', 'crashed'])

    for i in range(1000):
        ts = (start_time + timedelta(minutes=i)).isoformat()
        role = random.choice(roles)
        cpu = round(random.uniform(10.0, 99.9), 2)
        mem = round(random.uniform(1024.0, 16384.0), 2)

        # Artificial crash logic
        crashed = 1 if (cpu > 85.0 or mem > 14000) and random.random() > 0.2 else 0

        writer.writerow([ts, role, cpu, mem, crashed])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
