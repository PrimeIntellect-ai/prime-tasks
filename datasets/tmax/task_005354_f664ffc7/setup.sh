#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import csv

data = [
    ["server_id", "timestamp", "response_time"],
    ["web-01", "1000", "50"],
    ["web-02", "1001", "60"],
    ["web-01", "1002", "52"],
    ["web-03", "1002", "90"],
    ["web-01", "1003", "55"],
    ["web-01", "1004", "50"],
    ["web-01", "1005", "51"],
    ["web-01", "1006", "180"],
    ["web-01", "1007", "210"],
    ["web-02", "1007", "200"],
    ["web-01", "1008", "205"],
    ["web-01", "1009", "200"],
    ["web-01", "1010", "195"],
    ["web-01", "1011", "250"],
    ["web-01", "1012", "255"],
    ["web-01", "1013", "260"],
    ["web-01", "1014", "265"],
    ["web-01", "1015", "270"],
    ["web-01", "1016", "400"]
]

with open('/home/user/metrics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
