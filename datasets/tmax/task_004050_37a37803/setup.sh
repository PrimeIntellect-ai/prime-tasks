#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_csv.py
import csv

data = [
    ("timestamp", "sensor_id", "temperature", "error_code"),
    ("2023-10-01T12:00:00Z", 101, 22.5, 0),
    ("2023-10-01T12:01:00Z", 102, 18.0, ""),      # Missing error, treated as -1 -> valid
    ("2023-10-01T12:02:00Z", 101, 23.0, 1),       # Error code 1 -> discard
    ("2023-10-01T12:03:00Z", 103, 200.0, 0),      # Outlier temp -> discard
    ("2023-10-01T12:04:00Z", 101, 24.0, ""),      # Missing error -> valid
    ("2023-10-01T12:05:00Z", 102, 19.0, 0),       # Valid
    ("2023-10-01T12:06:00Z", 104, -60.0, ""),     # Outlier -> discard
    ("2023-10-01T12:07:00Z", 105, 45.5, 0),       # Valid
    ("2023-10-01T12:08:00Z", 105, 46.5, ""),      # Valid
]

with open("/home/user/sensors.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/create_csv.py
    rm /tmp/create_csv.py

    chmod -R 777 /home/user
