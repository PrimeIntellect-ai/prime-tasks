#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

random.seed(42)
filepath = '/home/user/sensor_data.csv'

with open(filepath, 'w') as f:
    f.write('id,s1,s2,s3,fault\n')
    for i in range(1, 500001):
        fault = 1 if random.random() < 0.05 else 0
        if fault == 1:
            s1 = 1 if random.random() < 0.85 else 0
            s2 = 1 if random.random() < 0.20 else 0
            s3 = 1 if random.random() < 0.90 else 0
        else:
            s1 = 1 if random.random() < 0.10 else 0
            s2 = 1 if random.random() < 0.50 else 0
            s3 = 1 if random.random() < 0.05 else 0
        f.write(f"{i},{s1},{s2},{s3},{fault}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
