#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest jupyter nbconvert papermill

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)

def generate_data():
    with open('/home/user/data/observations.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'sensor_id', 'value'])

        for i in range(5000):
            # S1
            v1 = min(max(random.gauss(0.5, 0.15), 0.0), 1.0)
            writer.writerow([f'T{i}', 'S1', round(v1, 4)])

            # S2
            v2 = min(max(random.gauss(0.5, 0.15), 0.0), 1.0)
            writer.writerow([f'T{i}', 'S2', round(v2, 4)])

            # S3
            v3 = min(max(random.betavariate(2, 5), 0.0), 1.0)
            writer.writerow([f'T{i}', 'S3', round(v3, 4)])

            # S4
            v4 = min(max(random.betavariate(5, 2), 0.0), 1.0)
            writer.writerow([f'T{i}', 'S4', round(v4, 4)])

if __name__ == '__main__':
    generate_data()
EOF
    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
