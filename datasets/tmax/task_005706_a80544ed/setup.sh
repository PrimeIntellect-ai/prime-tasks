#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import csv
from datetime import datetime, timedelta

data = [
    # Bucket 1: 10:00:00
    ("2023-10-01T10:01:15Z", "/api/login", 120.5, 200),
    ("2023-10-01T10:02:45Z", "/api/data", 240.0, 500), # error
    ("2023-10-01T10:04:10Z", "/api/login", 110.0, 200),
    ("2023-10-01T10:04:59Z", "/api/status", 50.0, 200),
    # Bucket 2: 10:05:00
    ("2023-10-01T10:05:01Z", "/api/data", 300.5, 200),
    ("2023-10-01T10:07:30Z", "/api/data", 310.0, 404), # error
    # Bucket 3: 10:10:00
    ("2023-10-01T10:12:00Z", "/api/login", 130.0, 401), # error
    ("2023-10-01T10:13:00Z", "/api/login", 125.0, 200),
    ("2023-10-01T10:14:00Z", "/api/login", 140.0, 403), # error
    ("2023-10-01T10:14:30Z", "/api/status", 60.0, 200),
]

with open('/home/user/server_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'endpoint', 'response_time_ms', 'status_code'])
    writer.writerows(data)
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
