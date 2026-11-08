#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.jsonl
{"id": 1, "name": "Alice B\u00f6hm", "email": "alice@example.com", "home_coords": [40.71, -74.00]}
{"id": 2, "name": "Bob Sm\u00ZZth", "email": "bob@domain.com", "home_coords": [34.05, -118.24]}
{"id": 3, "name": "Charlie \u12XY", "email": "charlie@test.org", "home_coords": [51.50, -0.12]}
EOF

    cat << 'EOF' > /home/user/transactions.jsonl
{"tx_id": "t1", "user_id": 1, "amount": 100.50, "tx_coords": [40.75, -73.98]}
{"tx_id": "t2", "user_id": 2, "amount": 25.00, "tx_coords": [34.00, -118.20]}
{"tx_id": "t3", "user_id": 3, "amount": 500.00, "tx_coords": [48.85, 2.35]}
{"tx_id": "t4", "user_id": 1, "amount": 10.00, "tx_coords": [55.00, -80.00]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
