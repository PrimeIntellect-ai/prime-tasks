#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)
start_time = datetime(2023, 10, 1, 10, 0, 0)

data = []

# Generate Profile A
for i in range(10):
    for _ in range(random.randint(1, 3)):
        ts = start_time + timedelta(minutes=i, seconds=random.randint(0, 59))
        latency = 50 + (i * 10 if i < 5 else (10-i)*10) + random.uniform(-2, 2)
        data.append((ts.isoformat(), "192.168.1.100", round(latency, 2)))

# Generate Profile B
for i in range(10):
    if i == 3 or i == 7: continue # Create gaps to test gap-filling
    for _ in range(random.randint(1, 3)):
        ts = start_time + timedelta(minutes=i, seconds=random.randint(0, 59))
        latency = 100 + (i * 20 if i < 5 else (10-i)*20) + random.uniform(-4, 4)
        data.append((ts.isoformat(), "10.0.0.5", round(latency, 2)))

# Generate Profile C
lat = 30
for i in range(10):
    for _ in range(random.randint(1, 3)):
        ts = start_time + timedelta(minutes=i, seconds=random.randint(0, 59))
        lat += random.uniform(-10, 10)
        data.append((ts.isoformat(), "172.16.0.8", round(lat, 2)))

# Generate Invalid IP
for _ in range(3):
    ts = start_time + timedelta(minutes=random.randint(0,9), seconds=random.randint(0, 59))
    data.append((ts.isoformat(), "8.8.8.8", round(random.uniform(10, 20), 2)))

# Shuffle data
random.shuffle(data)

with open("/home/user/api_latency.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "ip", "latency_ms"])
    writer.writerows(data)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
