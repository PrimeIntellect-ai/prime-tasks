#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random

data = [
    ("1", "D1", "20.0", "50.0"),
    ("2", "D1", "22.0", "51.0"),
    ("3", "D2", "19.0", "49.0"),
    ("4", "D1", "24.0", "50.0"),
    ("5", "D2", "21.0", "52.0"),
    ("6", "D1", "23.0", "50.0"),
    ("7", "D2", "20.0", "50.0"),
    ("8", "D2", "22.0", "51.0"),
]

with open('/home/user/telemetry.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'device_id', 'temperature', 'humidity'])
    writer.writerows(data)
EOF
    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
