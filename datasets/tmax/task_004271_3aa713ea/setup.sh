#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc sed grep
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import random
import csv

random.seed(42)
w1_true = 4.5
w2_true = -2.0
b_true = 1.5

with open('/home/user/training_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['x1', 'x2', 'y'])
    for _ in range(1000):
        x1 = random.uniform(-10, 10)
        x2 = random.uniform(-10, 10)
        # Add "floating point reduction order" noise simulation
        noise = random.gauss(0, 0.5)
        y = (w1_true * x1) + (w2_true * x2) + b_true + noise
        writer.writerow([round(x1, 4), round(x2, 4), round(y, 4)])
EOF
    chmod +x /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
