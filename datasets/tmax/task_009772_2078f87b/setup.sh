#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import os

os.makedirs('/home/user', exist_ok=True)

logs = [
    {"backup_id": "b1", "timestamp": "2023-10-01T01:00:00Z", "status": "SUCCESS", "size_bytes": 100, "database_name": "DB_ALPHA"},
    {"backup_id": "b2", "timestamp": "2023-10-02T01:00:00Z", "status": "SUCCESS", "size_bytes": 110, "database_name": "DB_ALPHA"},
    {"backup_id": "b3", "timestamp": "2023-10-03T01:00:00Z", "status": "SUCCESS", "size_bytes": 105, "database_name": "DB_ALPHA"},
    {"backup_id": "b_inv", "timestamp": "2023-10-04T01:00:00Z", "status": "SUCCESS", "size_bytes": "500", "database_name": "DB_ALPHA"},
    {"backup_id": "b4", "timestamp": "2023-10-05T01:00:00Z", "status": "SUCCESS", "size_bytes": 500, "database_name": "DB_ALPHA"},
    {"backup_id": "b5", "timestamp": "2023-10-01T02:00:00Z", "status": "SUCCESS", "size_bytes": 200, "database_name": "DB_BETA"},
    {"backup_id": "b6", "timestamp": "2023-10-02T02:00:00Z", "status": "SUCCESS", "size_bytes": 205, "database_name": "DB_BETA"},
    {"backup_id": "b7", "timestamp": "2023-10-03T02:00:00Z", "status": "FAILURE", "size_bytes": 20, "database_name": "DB_BETA"},
    {"backup_id": "b8", "timestamp": "2023-10-04T02:00:00Z", "status": "SUCCESS", "size_bytes": 190, "database_name": "DB_BETA"},
    {"backup_id": "b9", "timestamp": "2023-10-05T02:00:00Z", "status": "SUCCESS", "size_bytes": 210, "database_name": "DB_BETA"},
    {"backup_id": "b10", "timestamp": "2023-10-01T03:00:00Z", "status": "SUCCESS", "size_bytes": 500, "database_name": "DB_GAMMA"},
    {"backup_id": "b11", "timestamp": "2023-10-02T03:00:00Z", "status": "SUCCESS", "size_bytes": 500, "database_name": "DB_GAMMA"},
    {"backup_id": "b12", "timestamp": "2023-10-03T03:00:00Z", "status": "SUCCESS", "size_bytes": 400, "database_name": "DB_GAMMA"}
]

with open('/home/user/backup_logs.jsonl', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
