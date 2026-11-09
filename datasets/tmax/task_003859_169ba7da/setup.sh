#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/compliance_audit
    cd /home/user/compliance_audit

    cat << 'EOF' > generate_data.py
import csv
import random

random.seed(42)

with open('tx_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['tx_id', 'sender_id', 'receiver_id', 'amount', 'timestamp'])

    tx_id = 1

    # Generate background noise
    for _ in range(10000):
        sender = f"U{random.randint(1000, 9999)}"
        receiver = f"U{random.randint(1000, 9999)}"
        amount = round(random.uniform(10.0, 100000.0), 2)
        writer.writerow([tx_id, sender, receiver, amount, "2023-01-01T12:00:00Z"])
        tx_id += 1

    # Generate specific cycles (A->B->C->A) > 50000
    cycles = [
        ("U1111", "U2222", "U3333", 55000.0, 60000.0, 75000.0),
        ("U4444", "U5555", "U6666", 80000.0, 90000.0, 85000.0),
        ("U7777", "U8888", "U9999", 51000.0, 52000.0, 49000.0), # One edge < 50000, should be ignored
    ]

    for c in cycles:
        writer.writerow([tx_id, c[0], c[1], c[3], "2023-01-02T12:00:00Z"]); tx_id += 1
        writer.writerow([tx_id, c[1], c[2], c[4], "2023-01-02T12:00:00Z"]); tx_id += 1
        writer.writerow([tx_id, c[2], c[0], c[5], "2023-01-02T12:00:00Z"]); tx_id += 1

EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
