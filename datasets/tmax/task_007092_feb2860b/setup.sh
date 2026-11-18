#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_events.json
[
  {"user_id": "u1", "action": "VIEWED", "product_id": "p1", "timestamp": "2023-10-01T10:00:00Z"},
  {"user_id": "u1", "action": "VIEWED", "product_id": "p1", "timestamp": "2023-10-01T10:05:00Z"},
  {"user_id": "u2", "action": "PURCHASED", "product_id": "p1", "timestamp": "2023-10-01T10:10:00Z"},
  {"user_id": "u2", "action": "VIEWED", "product_id": "p2", "timestamp": "2023-10-01T10:15:00Z"},
  {"user_id": "u1", "action": "VIEWED", "product_id": "p2", "timestamp": "2023-10-01T10:20:00Z"},
  {"user_id": "u3", "action": "VIEWED", "product_id": "p1", "timestamp": "2023-10-01T10:25:00Z"},
  {"user_id": "u3", "action": "VIEWED", "product_id": "p1", "timestamp": "2023-10-01T10:30:00Z"},
  {"user_id": "u3", "action": "VIEWED", "product_id": "p1", "timestamp": "2023-10-01T10:35:00Z"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
