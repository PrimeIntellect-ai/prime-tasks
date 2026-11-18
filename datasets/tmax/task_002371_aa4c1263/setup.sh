#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.jsonl
{"tx_id": "T001", "sender": "Alice", "receiver": "Bob", "amount": 100.0, "timestamp": "2023-10-01T10:00:00Z"}
{"tx_id": "T002", "sender": "Bob", "receiver": "Alice", "amount": 50.0, "timestamp": "2023-10-01T10:00:00Z"}
{"tx_id": "T003", "sender": "Charlie", "receiver": "Dave", "amount": 20.0, "timestamp": "2023-10-01T11:00:00Z"}
{"tx_id": "T004", "sender": "Dave", "receiver": "Charlie", "amount": 30.0, "timestamp": "2023-10-01T11:00:01Z"}
{"tx_id": "T005", "sender": "Eve", "receiver": "Frank", "amount": 200.0, "timestamp": "2023-10-01T12:30:15Z"}
{"tx_id": "T007", "sender": "Frank", "receiver": "Eve", "amount": 150.0, "timestamp": "2023-10-01T12:30:15Z"}
{"tx_id": "T008", "sender": "Alice", "receiver": "Charlie", "amount": 10.0, "timestamp": "2023-10-01T14:00:00Z"}
{"tx_id": "T009", "sender": "George", "receiver": "Hannah", "amount": 40.0, "timestamp": "2023-10-02T09:00:00Z"}
{"tx_id": "T010", "sender": "Hannah", "receiver": "George", "amount": 40.0, "timestamp": "2023-10-02T09:00:00Z"}
EOF

    chmod -R 777 /home/user
