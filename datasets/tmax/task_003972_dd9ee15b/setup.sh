#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_logs.py
import csv

data = [
    ("1", "2023-10-15T14:35:12Z", "INFO: System started normally\nNo issues found."),
    ("2", "2023-10-15T14:40:00Z", "CRITICAL: Disk failure detected in /dev/sda1\nPlease replace immediately."),
    ("3", "2023-10-15T14:55:10Z", "CRITICAL: Disk failure detected in /dev/sdb2\nVolume degraded."),
    ("4", "2023-10-15T15:10:00Z", "WARNING: CPU usage at 95%"),
    ("5", "2023-10-15T15:15:20Z", "CRITICAL: Memory leak in process 1024\nOOM killer invoked."),
    ("6", "2023-10-16T02:05:00Z", "CRITICAL: Disk failure detected in /dev/sda1"),
    ("7", "2023-10-16T02:45:00Z", "CRITICAL: Disk failure detected in /dev/sdc3\nCheck array."),
    ("8", "2023-10-16T03:10:00Z", "ERROR: Network timeout"),
]

with open('/home/user/system_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["event_id", "timestamp", "message"])
    for row in data:
        writer.writerow(row)
EOF
    python3 /home/user/create_logs.py
    rm /home/user/create_logs.py

    chmod -R 777 /home/user
