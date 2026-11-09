#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup_data.py
import csv
import os

os.makedirs('/home/user/data', exist_ok=True)

data = [
    ["timestamp", "level", "message"],
    ["2023-10-01T14:12:33Z", "INFO", "System startup initiated.\nAll services normal."],
    ["2023-10-01T14:45:00Z", "ERROR", "Database connection failed.\nRetrying...\nErrorCode: SYS-1029\nMore info below."],
    ["2023-10-01T15:05:11Z", "ERROR", "Memory limit exceeded.\nErrorCode: APP-0001"],
    ["2023-10-01T15:30:00Z", "ERROR", "Unhandled exception occurred.\nNo code here \njust vibes"],
    ["2023-10-01T14:55:00Z", "ERROR", "Secondary DB failure.\nErrorCode: SYS-1029"],
    ["2023-10-01T14:59:59Z", "WARN", "High latency detected.\nErrorCode: SYS-1029"],
    ["2023-10-02T09:15:00Z", "ERROR", "Network timeout.\nErrorCode: NET-4044\nPlease check router."],
    ["2023-10-02T09:25:00Z", "ERROR", "Packet loss.\nErrorCode:NET-4044"],
    ["2023-10-02T10:01:00Z", "INFO", "User login successful.\nUser: admin"],
    ["2023-10-02T10:15:00Z", "ERROR", "Permission denied.\nErrorCode: AUTH-0403\nAttempted access to restricted resource."]
]

with open('/home/user/data/input.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
