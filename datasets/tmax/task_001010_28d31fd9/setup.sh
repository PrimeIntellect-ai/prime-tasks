#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import random

os.makedirs('/home/user', exist_ok=True)
random.seed(42)

with open('/home/user/raw_embeddings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'v0', 'v1', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7'])
    for i in range(10000):
        row = [i] + [random.gauss(0.5, 2.0)] + [random.gauss(0.0, 2.0) for _ in range(7)]
        writer.writerow(row)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
