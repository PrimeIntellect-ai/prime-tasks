#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/input

    cat << 'EOF' > /tmp/generate_data.py
import csv

data = [
    ["id", "category", "temp_c", "pressure_psi", "raw_log"],
    [1, "A", 22.5, 14.1, "System started.\nCODE: SYS-0001\nAll good."],
    [2, "A", 22.7, 14.2, "Running. CODE: RUN-0002"],
    [3, "A", 23.1, 14.0, "Spike detected.\nCODE: ERR-0999"],
    [4, "B", 18.0, 15.5, "Cooling. CODE: COL-1001"],
    [5, "B", 18.1, 15.4, "CODE: COL-1002\nStable."],
    [6, "B", 18.2, 15.5, "CODE: COL-1003"],
]

with open('/home/user/input/sensor_log.csv', 'w', encoding='utf-16le', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
