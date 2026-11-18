#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas networkx

mkdir -p /home/user

cat << 'EOF' > /tmp/setup.py
import json
import csv
import os

os.makedirs("/home/user", exist_ok=True)

metadata = [{"tx_id": f"T{i}", "start_time": 1000 + i, "user": f"user_{i}"} for i in range(1, 10)]
with open("/home/user/tx_metadata.json", "w") as f:
    json.dump(metadata, f)

edges = [
    {"waiter_tx": "T1", "holder_tx": "T2", "wait_timestamp": 120},
    {"waiter_tx": "T2", "holder_tx": "T3", "wait_timestamp": 110},
    {"waiter_tx": "T3", "holder_tx": "T1", "wait_timestamp": 150},
    {"waiter_tx": "T4", "holder_tx": "T5", "wait_timestamp": 140},
    {"waiter_tx": "T5", "holder_tx": "T4", "wait_timestamp": 180},
    {"waiter_tx": "T6", "holder_tx": "T7", "wait_timestamp": 130},
    {"waiter_tx": "T7", "holder_tx": "T8", "wait_timestamp": 135},
    {"waiter_tx": "T1", "holder_tx": "T6", "wait_timestamp": 160} # extraneous edge
]

with open("/home/user/lock_waits.csv", "w", newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["waiter_tx", "holder_tx", "wait_timestamp"])
    writer.writeheader()
    writer.writerows(edges)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
