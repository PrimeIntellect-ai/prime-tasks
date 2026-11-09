#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import random

random.seed(42)
ops = ['+', '*']
with open('/home/user/dataset.txt', 'w') as f:
    for _ in range(10000):
        v1 = random.uniform(-100.0, 100.0)
        v2 = random.uniform(-100.0, 100.0)
        v3 = random.uniform(-100.0, 100.0)
        op1 = random.choice(ops)
        op2 = random.choice(ops)
        f.write(f"{v1:.6f} {op1} {v2:.6f} {op2} {v3:.6f}\n")
EOF
    python3 /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
