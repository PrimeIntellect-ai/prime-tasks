#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/cleaned_data

    cat << 'EOF' > /home/user/generate_data.py
import csv
import random

random.seed(42)

def generate_dataset(filename, m, b, n_points, n_outliers):
    data = []
    for _ in range(n_points):
        x = random.uniform(0, 100)
        y = m * x + b + random.gauss(0, 2)
        data.append((x, y))

    for _ in range(n_outliers):
        x = random.uniform(0, 100)
        y = m * x + b + random.choice([20, -20, 25, -25])
        data.append((x, y))

    random.shuffle(data)

    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        for x, y in data:
            writer.writerow([f"{x:.4f}", f"{y:.4f}"])

generate_dataset('/home/user/raw_data/sensor_A.csv', 2.5, 10.0, 100, 4)
generate_dataset('/home/user/raw_data/sensor_B.csv', -1.2, 50.0, 150, 6)
generate_dataset('/home/user/raw_data/sensor_C.csv', 0.5, -5.0, 200, 8)
EOF

    python3 /home/user/generate_data.py

    chmod -R 777 /home/user
