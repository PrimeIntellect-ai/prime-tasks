#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv sqlite3
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_logs.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)
start_time = datetime(2023, 10, 1, 10, 0, 0)
records = []

# Generate 2 hours of logs
for i in range(120 * 6): # roughly 10 seconds per log
    t = start_time + timedelta(seconds=i*10 + random.randint(0, 5))
    ip = f"{random.randint(10, 200)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"
    endpoint = random.choice(["/home", "/api/data", "/login", "/checkout"])

    # Introduce anomaly between 11:15 and 11:25
    is_anomaly_window = datetime(2023, 10, 1, 11, 15, 0) <= t <= datetime(2023, 10, 1, 11, 25, 0)

    if is_anomaly_window:
        status = random.choice([200, 200, 404, 500, 502]) # High error rate
    else:
        status = random.choice([200]*20 + [404, 500]) # Low error rate

    rt = random.randint(50, 500)
    records.append([t.strftime("%Y-%m-%d %H:%M:%S"), ip, endpoint, status, rt])

records.sort(key=lambda x: x[0])

with open('/home/user/raw_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'ip_address', 'endpoint', 'status_code', 'response_time_ms'])
    writer.writerows(records)
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
