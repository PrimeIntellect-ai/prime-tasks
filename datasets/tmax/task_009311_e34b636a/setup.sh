#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random

random.seed(42)
with open("/home/user/raw_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "f1", "f2", "f3"])
    for i in range(1, 1001):
        f1 = random.uniform(0, 10)
        f2 = random.uniform(0, 10)
        f3 = random.uniform(0, 10)
        writer.writerow([i, f"{f1:.4f}", f"{f2:.4f}", f"{f3:.4f}"])
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
