#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.json
[
  {"id": 1, "name": "Alice"},
  {"id": 2, "name": "Bob"},
  {"id": 3, "name": "Charlie"},
  {"id": 4, "name": "Diana"}
]
EOF

    cat << 'EOF' > /home/user/transactions.json
[
  {"tx_id": 101, "user_id": 1, "amount": 100, "status": "COMPLETED"},
  {"tx_id": 102, "user_id": 1, "amount": 60, "status": "COMPLETED"},
  {"tx_id": 103, "user_id": 2, "amount": 200, "status": "COMPLETED"},
  {"tx_id": 104, "user_id": 2, "amount": 50, "status": "PENDING"},
  {"tx_id": 105, "user_id": 3, "amount": 120, "status": "COMPLETED"},
  {"tx_id": 106, "user_id": 4, "amount": 300, "status": "FAILED"}
]
EOF

    chmod -R 777 /home/user
