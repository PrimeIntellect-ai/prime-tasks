#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas numpy scipy scikit-learn jinja2

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import os

os.makedirs('/home/user', exist_ok=True)
log_path = '/home/user/raw_logs.csv'

# Generate synthetic logs
random.seed(42)
users = [f"U{i:03d}" for i in range(1, 101)]

with open(log_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'timestamp', 'source_ip', 'bytes_sent'])

    # Normal users
    for user in users[:95]:
        num_req = random.randint(40, 60)
        ip = f"192.168.1.{random.randint(10, 20)}"
        for _ in range(num_req):
            writer.writerow([user, '2023-10-01 10:00:00', ip, random.randint(2000, 3000)])

    # Anomalous users
    for _ in range(10):
        writer.writerow(['U096', '2023-10-01 10:00:00', f"10.0.0.{random.randint(1,10)}", 2500])
    for _ in range(50):
        writer.writerow(['U097', '2023-10-01 10:00:00', '192.168.1.99', 50000])
    for _ in range(500):
        writer.writerow(['U098', '2023-10-01 10:00:00', '192.168.1.100', 2500])
    for _ in range(200):
        writer.writerow(['U099', '2023-10-01 10:00:00', f"172.16.0.{random.randint(1,50)}", 80000])
    for _ in range(2):
        writer.writerow(['U100', '2023-10-01 10:00:00', '192.168.1.101', 10])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
