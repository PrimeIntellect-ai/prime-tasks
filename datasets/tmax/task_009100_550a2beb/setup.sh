#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

os.makedirs('/home/user', exist_ok=True)

random.seed(123)
with open('/home/user/reference.txt', 'w') as f:
    for _ in range(10000):
        if random.random() < 0.3:
            v = random.uniform(0.0, 0.5)
        else:
            v = random.uniform(0.2, 1.0)
        f.write(f"{v:.6f}\n")

random.seed(456)
with open('/home/user/sample.txt', 'w') as f:
    for _ in range(1000):
        if random.random() < 0.3:
            v = random.uniform(0.0, 0.5)
        else:
            v = random.uniform(0.2, 1.0)
        f.write(f"{v:.6f}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
