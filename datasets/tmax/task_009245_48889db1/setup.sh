#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_logs.py
import json

logs = []

# Non-transfer noise
logs.append({"timestamp": "2023-10-01", "type": "LOGIN", "sender_id": "U001"})

# U001: 10 distinct receivers (Hub 1)
for i in range(10):
    logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U001", "receiver_id": f"R1{i}", "amount": 60000, "status": "COMPLETED"})

# U002: 8 distinct receivers
for i in range(8):
    logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U002", "receiver_id": f"R2{i}", "amount": 60000, "status": "COMPLETED"})

# U003: 8 distinct receivers
for i in range(8):
    logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U003", "receiver_id": f"R3{i}", "amount": 60000, "status": "COMPLETED"})

# U004: 6 distinct receivers, plus 2 failed ones, plus 2 low amount ones
for i in range(6):
    logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U004", "receiver_id": f"R4{i}", "amount": 60000, "status": "COMPLETED"})
logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U004", "receiver_id": "R498", "amount": 60000, "status": "FAILED"})
logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U004", "receiver_id": "R499", "amount": 40000, "status": "COMPLETED"})

# U005: 5 distinct receivers
for i in range(5):
    logs.append({"timestamp": "2023-10-01", "type": "TRANSFER", "sender_id": "U005", "receiver_id": f"R5{i}", "amount": 60000, "status": "COMPLETED"})

# Duplicate transfers for U002 to test "distinct" count
logs.append({"timestamp": "2023-10-02", "type": "TRANSFER", "sender_id": "U002", "receiver_id": "R20", "amount": 70000, "status": "COMPLETED"})

import random
random.seed(42)
random.shuffle(logs)

with open("/home/user/audit_logs.jsonl", "w") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")
EOF

    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
