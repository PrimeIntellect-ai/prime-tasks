#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import csv

data = [
    ('S', 'A', 10.0, 1),
    ('S', 'A', 5.0, 2),
    ('S', 'B', 8.0, 1),
    ('A', 'C', 2.0, 1),
    ('A', 'C', 15.0, 2),
    ('B', 'C', 4.0, 1),
    ('C', 'D', 3.0, 1),
    ('B', 'D', 10.0, 1),
    ('D', 'T', 5.0, 1),
    ('A', 'T', 25.0, 1),
    ('C', 'T', 12.0, 1),
    ('C', 'T', 18.0, 0),
    ('S', 'B', 9.0, 0)
]

with open('/home/user/routes.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target', 'distance', 'last_updated'])
    writer.writerows(data)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
