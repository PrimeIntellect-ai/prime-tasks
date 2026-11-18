#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(123)
with open('/home/user/data/sensor_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'sensor_x', 'sensor_y'])
    for i in range(1, 501):
        if random.random() < 0.05:
            # missing value
            writer.writerow([i, '', random.uniform(10, 20)])
        elif random.random() < 0.05:
            # NaN
            writer.writerow([i, random.uniform(10, 20), 'NaN'])
        elif random.random() < 0.05:
            # Outlier
            writer.writerow([i, random.uniform(5000, 10000), random.uniform(10, 20)])
        else:
            # Clean data: y = 3.5 * x + 2.0 + noise
            x = random.uniform(0, 100)
            y = 3.5 * x + 2.0 + random.uniform(-5, 5)
            writer.writerow([i, round(x, 4), round(y, 4)])
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
