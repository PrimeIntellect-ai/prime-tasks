#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/raw_data', exist_ok=True)

statuses = ['SUCCESS', 'FAILED', 'OK', 'ERROR-500', 'ERROR-TIMEOUT', 'ERROR-404']

with open('/home/user/raw_data/experiments.log', 'w') as f:
    for i in range(1, 101):
        run_id = f"EXP-{i:05d}"
        status = random.choice(statuses)
        f.write("=== RUN START ===\n")
        f.write(f"RunID: {run_id}\n")
        f.write(f"Status: {status}\n")
        f.write(f"Date: 2023-10-{random.randint(1, 28):02d}\n")
        f.write("Measurements:\n")
        for _ in range(3):
            f.write(f"val_{random.randint(1,10)}={random.random():.4f}\n")
        f.write("=== RUN END ===\n\n")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
