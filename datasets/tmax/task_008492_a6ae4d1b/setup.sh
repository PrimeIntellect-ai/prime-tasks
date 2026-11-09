#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.json
[
  {"tx_id": 201, "waiting_for_tx": 202, "duration": 100, "query": "UPDATE users"},
  {"tx_id": 202, "waiting_for_tx": 203, "duration": 60, "query": "DELETE from logs"},
  {"tx_id": 203, "waiting_for_tx": 204, "duration": 70, "query": "UPDATE config"},
  {"tx_id": 204, "waiting_for_tx": 205, "duration": 40, "query": "INSERT into audit"},
  {"tx_id": 205, "waiting_for_tx": 202, "duration": 90, "query": "UPDATE permissions"},
  {"tx_id": 206, "waiting_for_tx": 205, "duration": 120, "query": "SELECT * FROM users"},
  {"tx_id": 207, "waiting_for_tx": 201, "duration": 80, "query": "DELETE from tmp"},
  {"tx_id": 208, "waiting_for_tx": null, "duration": 150, "query": "SELECT count(*) FROM audit"}
]
EOF

    chmod -R 777 /home/user
