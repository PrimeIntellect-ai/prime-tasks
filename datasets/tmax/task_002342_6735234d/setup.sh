#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import csv
import random

random.seed(42)
rows = 150
cols = 4

with open('/home/user/data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for _ in range(rows):
        # Generate some synthetic data with variance
        row = [
            random.gauss(10, 2.5),
            random.gauss(-5, 1.2),
            random.gauss(0, 5.0),
            random.gauss(100, 10.0)
        ]
        writer.writerow(row)
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
