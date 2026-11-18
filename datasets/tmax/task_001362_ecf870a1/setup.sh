#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libcjson-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.jsonl
{"user_id": "U01", "name": "Alice", "region": "North"}
{"user_id": "U02", "name": "Bob", "region": "South"}
{"user_id": "U03", "name": "Charlie", "region": "East"}
{"user_id": "U04", "name": "Diana", "region": "West"}
{"user_id": "U05", "name": "Eve", "region": "North"}
EOF

    cat << 'EOF' > /home/user/orders.jsonl
{"order_id": "O01", "user_id": "U01", "total": 150, "status": "completed"}
{"order_id": "O02", "user_id": "U01", "total": 50, "status": "completed"}
{"order_id": "O03", "user_id": "U02", "total": 200, "status": "pending"}
{"order_id": "O04", "user_id": "U02", "total": 300, "status": "completed"}
{"order_id": "O05", "user_id": "U03", "total": 120, "status": "completed"}
{"order_id": "O06", "user_id": "U04", "total": 500, "status": "completed"}
{"order_id": "O07", "user_id": "U05", "total": 110, "status": "completed"}
{"order_id": "O08", "user_id": "U05", "total": 200, "status": "completed"}
EOF

    chown -R user:user /home/user/*.jsonl
    chmod -R 777 /home/user
