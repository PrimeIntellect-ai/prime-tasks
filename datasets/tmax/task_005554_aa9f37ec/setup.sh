#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv

data = [
    ["LogID", "Message"],
    [1, "  Temperature sensor anomaly \xA9"],
    [2, "temperature sensor anomaly \xA9"],
    [3, "  Pressure sensor reading: 45 kPa  "],
    [4, " Pressure sensor reading: 46 kPa"],
    [5, "System restart initiated"],
    [6, " system restart initiated \t"],
    [7, "System shutdown initiated"]
]

with open('/home/user/sensor_logs.csv', 'w', encoding='cp1252', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
