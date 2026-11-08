#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas duckdb

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import json

events = [
    {"msg_id": 1, "sender": "Alice", "receiver": "Bob", "timestamp": "2023-10-01T10:00:00", "bytes": 100},
    {"msg_id": 2, "sender": "Bob", "receiver": "Charlie", "timestamp": "2023-10-01T10:05:00", "bytes": 200},
    {"msg_id": 3, "sender": "Alice", "receiver": "Charlie", "timestamp": "2023-10-01T10:10:00", "bytes": 150},
    {"msg_id": 4, "sender": "Charlie", "receiver": "Alice", "timestamp": "2023-10-01T10:15:00", "bytes": 50},
    {"msg_id": 5, "sender": "David", "receiver": "Alice", "timestamp": "2023-10-01T10:20:00", "bytes": 300},
    {"msg_id": 6, "sender": "Alice", "receiver": "David", "timestamp": "2023-10-01T10:25:00", "bytes": 100},
    {"msg_id": 7, "sender": "Bob", "receiver": "Alice", "timestamp": "2023-10-01T10:30:00", "bytes": 250},
    {"msg_id": 8, "sender": "Alice", "receiver": "Eve", "timestamp": "2023-10-01T10:35:00", "bytes": 80},
    {"msg_id": 9, "sender": "Eve", "receiver": "Alice", "timestamp": "2023-10-01T10:40:00", "bytes": 90},
    {"msg_id": 10, "sender": "Alice", "receiver": "Bob", "timestamp": "2023-10-01T10:45:00", "bytes": 120},
    {"msg_id": 11, "sender": "Charlie", "receiver": "Bob", "timestamp": "2023-10-01T10:50:00", "bytes": 60},
    {"msg_id": 12, "sender": "Bob", "receiver": "David", "timestamp": "2023-10-01T10:55:00", "bytes": 210},
    {"msg_id": 13, "sender": "David", "receiver": "Bob", "timestamp": "2023-10-01T11:00:00", "bytes": 310},
    {"msg_id": 14, "sender": "Alice", "receiver": "Charlie", "timestamp": "2023-10-01T11:05:00", "bytes": 140},
    {"msg_id": 15, "sender": "Bob", "receiver": "Eve", "timestamp": "2023-10-01T11:10:00", "bytes": 220},
    {"msg_id": 16, "sender": "Eve", "receiver": "Charlie", "timestamp": "2023-10-01T11:15:00", "bytes": 95},
    {"msg_id": 17, "sender": "Charlie", "receiver": "David", "timestamp": "2023-10-01T11:20:00", "bytes": 70},
    {"msg_id": 18, "sender": "Alice", "receiver": "David", "timestamp": "2023-10-01T11:25:00", "bytes": 110},
    {"msg_id": 19, "sender": "David", "receiver": "Eve", "timestamp": "2023-10-01T11:30:00", "bytes": 320},
    {"msg_id": 20, "sender": "Bob", "receiver": "Alice", "timestamp": "2023-10-01T11:35:00", "bytes": 260}
]

with open('/home/user/data/messages.jsonl', 'w') as f:
    for e in events:
        f.write(json.dumps(e) + '\n')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
