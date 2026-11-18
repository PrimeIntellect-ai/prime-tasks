#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random

services = ['auth-service', 'payment-gateway', 'db-worker', 'frontend-app']
levels = ['ERROR', 'Error', 'error', 'WARNING', 'warning', 'INFO', 'info']

with open('/home/user/system_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'level', 'service', 'message'])
    random.seed(42)
    for i in range(1000):
        svc = random.choice(services)
        lvl = random.choice(levels)
        msg = f"User action {i}"
        if random.random() < 0.2:
            msg += "\nDetails:\nStack trace here"
        writer.writerow([f"2023-10-01T12:00:{i%60:02d}Z", lvl, svc, msg])
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
