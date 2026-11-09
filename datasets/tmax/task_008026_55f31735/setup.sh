#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/scripts
    mkdir -p /home/user/db
    mkdir -p /home/user/results

    cat << 'EOF' > /home/user/generate_data.py
import json

events = [
    {"event_type": "login", "user": "A", "timestamp": 100},
    {"event_type": "transfer", "status": "success", "sender": "A", "receiver": "B", "timestamp": 101, "amount": 10.0},
    {"event_type": "transfer", "status": "success", "sender": "B", "receiver": "C", "timestamp": 102, "amount": 20.0},
    {"event_type": "transfer", "status": "success", "sender": "C", "receiver": "D", "timestamp": 103, "amount": 30.0}, # Path A: A->D total 60

    {"event_type": "transfer", "status": "success", "sender": "A", "receiver": "X", "timestamp": 105, "amount": 50.0},
    {"event_type": "transfer", "status": "success", "sender": "X", "receiver": "Y", "timestamp": 106, "amount": 10.0},
    {"event_type": "transfer", "status": "success", "sender": "Y", "receiver": "Z", "timestamp": 107, "amount": 5.0}, # Path A2: A->Z total 65 (Rank 1 for A)

    {"event_type": "transfer", "status": "success", "sender": "U1", "receiver": "U2", "timestamp": 200, "amount": 100.0},
    {"event_type": "transfer", "status": "success", "sender": "U2", "receiver": "U3", "timestamp": 201, "amount": 200.0},
    {"event_type": "transfer", "status": "success", "sender": "U3", "receiver": "U4", "timestamp": 202, "amount": 300.0}, # Path U1: U1->U4 total 600

    {"event_type": "transfer", "status": "failed", "sender": "F1", "receiver": "F2", "timestamp": 300, "amount": 1000.0},

    {"event_type": "transfer", "status": "success", "sender": "K1", "receiver": "K2", "timestamp": 400, "amount": 50.0},
    {"event_type": "transfer", "status": "success", "sender": "K2", "receiver": "K3", "timestamp": 401, "amount": 50.0},
    {"event_type": "transfer", "status": "success", "sender": "K3", "receiver": "K4", "timestamp": 402, "amount": 50.0}, # Path K1: K1->K4 total 150

    {"event_type": "transfer", "status": "success", "sender": "M1", "receiver": "M2", "timestamp": 500, "amount": 15.0},
    {"event_type": "transfer", "status": "success", "sender": "M2", "receiver": "M3", "timestamp": 501, "amount": 15.0},
    {"event_type": "transfer", "status": "success", "sender": "M3", "receiver": "M4", "timestamp": 502, "amount": 15.0}, # Path M1: M1->M4 total 45

    {"event_type": "transfer", "status": "success", "sender": "N1", "receiver": "N2", "timestamp": 600, "amount": 1.0},
    {"event_type": "transfer", "status": "success", "sender": "N2", "receiver": "N3", "timestamp": 601, "amount": 1.0},
    {"event_type": "transfer", "status": "success", "sender": "N3", "receiver": "N4", "timestamp": 602, "amount": 1.0}, # Path N1: N1->N4 total 3
]

with open('/home/user/data/transactions.jsonl', 'w') as f:
    for e in events:
        f.write(json.dumps(e) + '\n')
EOF

    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
