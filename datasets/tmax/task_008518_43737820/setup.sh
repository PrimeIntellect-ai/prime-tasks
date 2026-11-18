#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.jsonl
{"_id": "u1", "email": "alice@example.com", "name": "Alice"}
{"_id": "u2", "email": "bob@example.com", "name": "Bob"}
{"_id": "u3", "email": "charlie@example.com", "name": "Charlie"}
EOF

    cat << 'EOF' > /home/user/data/orders.jsonl
{"order_id": "o1", "u_id": "u1", "items": [{"name": "Laptop", "category": "electronics", "price": 1200.00}, {"name": "Mouse", "category": "electronics", "price_cents": 2500}]}
{"order_id": "o2", "u_id": "u1", "items": [[{"name": "Pen", "category": "office", "cost": "$1.50"}, {"name": "Notebook", "category": "office", "cost": "$5.00"}]]}
{"order_id": "o3", "u_id": "u2", "items": [{"name": "Keyboard", "category": "electronics", "price_cents": 7500}]}
{"order_id": "o4", "u_id": "u3", "items": [{"name": "Desk", "category": "furniture", "price": 200.00}, {"name": "Chair", "category": "furniture", "price": 150.00}]}
{"order_id": "o5", "u_id": "u3", "items": [{"name": "Lamp", "category": "furniture", "price_cents": 4500}, {"name": "Bulb", "category": "electronics", "cost": "$5.00"}]}
EOF

    chmod -R 777 /home/user
