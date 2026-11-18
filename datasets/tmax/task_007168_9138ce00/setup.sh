#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/users.csv
user_id,name,email,ssn
1,Alice Smith,alice.smith@example.com,111-22-3333
2,Bob Jones,bob.jones@test.org,444-55-6666
3,Charlie Brown,cbrown@corp.com,999-88-7777
EOF

    cat << 'EOF' > /home/user/data/transactions.json
[
  {"tx_id": "tx1", "user_id": 1, "amount": 100, "timestamp": "2023-01-01T10:00:00Z", "description": "Grocery store purchase"},
  {"tx_id": "tx2", "user_id": 1, "amount": 120, "timestamp": "2023-01-02T11:00:00Z", "description": "Gas station!"},
  {"tx_id": "tx3", "user_id": 1, "amount": 110, "timestamp": "2023-01-03T09:00:00Z", "description": "Coffee shop - morning"},
  {"tx_id": "tx4", "user_id": 1, "amount": 5000, "timestamp": "2023-01-04T15:00:00Z", "description": "LUXURY watch purchase..."},
  {"tx_id": "tx5", "user_id": 2, "amount": 50, "timestamp": "2023-01-01T12:00:00Z", "description": "Fast food"},
  {"tx_id": "tx6", "user_id": 2, "amount": 60, "timestamp": "2023-01-02T13:00:00Z", "description": "Books & magazines"},
  {"tx_id": "tx7", "user_id": 2, "amount": 55, "timestamp": "2023-01-03T14:00:00Z", "description": "Movies"},
  {"tx_id": "tx8", "user_id": 2, "amount": 200, "timestamp": "2023-01-04T18:00:00Z", "description": "Fancy Dinner at 8pm"},
  {"tx_id": "tx9", "user_id": 3, "amount": 10, "timestamp": "2023-01-01T10:00:00Z", "description": "Snacks"}
]
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
