#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pytz pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import pytz
from datetime import datetime

data = [
    ("2024-03-01 10:00:00", "UTC", "srv-A", "OOM", "Memory limit exceeded\nTraceback..."),
    ("2024-03-01 06:00:00", "America/New_York", "srv-B", "DB_Timeout", "Timeout waiting for DB\nLine 1\nLine 2"),
    ("2024-03-01 20:00:00", "Asia/Tokyo", "srv-A", "Auth_Failure", "Invalid token\nHeader invalid"),
    ("2024-02-29 21:00:00", "America/Los_Angeles", "srv-C", "OOM", "OOM inside container\n..."),
    ("2024-02-28 10:00:00", "UTC", "srv-A", "OOM", "Old OOM\n..."),
    ("2024-03-02 09:00:00", "Asia/Tokyo", "srv-B", "DB_Timeout", "Future timeout"),
]

with open('/home/user/raw_logs.csv', 'w', encoding='utf-16le', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["local_time", "timezone", "server", "error_category", "details"])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
