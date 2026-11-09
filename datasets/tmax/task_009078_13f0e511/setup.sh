#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 << 'EOF'
import os
import csv
import random

random.seed(42)
users = []
for i in range(1, 51):
    target = 1 if random.random() > 0.6 else 0
    num_tx = random.randint(1, 10)
    users.append((i, num_tx, target))

tx_id = 1
filepath = '/home/user/raw_transactions.csv'
os.makedirs(os.path.dirname(filepath), exist_ok=True)

with open(filepath, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['tx_id', 'user_id', 'amount', 'target'])
    for u_id, num_tx, target in users:
        for _ in range(num_tx):
            amount = round(random.uniform(5.0, 150.0), 2)
            writer.writerow([tx_id, u_id, amount, target])
            tx_id += 1
EOF

    chmod -R 777 /home/user
