#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv

data = [
    (1, 10.0, 0, 1),
    (2, 11.2, 0, 1),
    (3, 9.5, 0, 1),
    (4, 25.0, 1, 1),
    (5, 10.1, 0, 1),
    (6, 9.8, 0, 2),
    (7, 10.5, 0, 2),
    (8, 10.2, 0, 2),
    (9, 2.0, 1, 2),
    (10, 10.0, 0, 2),
    (11, 10.1, 0, 3),
    (12, 10.3, 0, 3),
    (13, 9.9, 0, 3),
    (14, 28.0, 1, 3),
    (15, 10.4, 0, 3)
]

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'value', 'label', 'fold'])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
