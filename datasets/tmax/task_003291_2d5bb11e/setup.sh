#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest python-dateutil dateparser

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_configs.jsonl
{"host_id": "web-01", "recorded_at": "2023-01-01T12:00:00Z", "state": {"port": 80, "api_key": "sk-live-12345"}}
{"host_id": "web-01", "recorded_at": "Sun, 01 Jan 2023 12:05:00 GMT", "state": {"port": 80, "api_key": "sk-live-12345"}}
{"host_id": "db-01", "recorded_at": "2023-01-01 13:00:00", "state": {"max_connections": 100, "password": "supersecret"}}
{"host_id": "web-01", "recorded_at": "2023-01-01T14:00:00Z", "state": {"port": 443, "api_key": "sk-live-12345"}}
{"host_id": "db-01", "recorded_at": "2023-01-01 15:00:00+00:00", "state": {"max_connections": 100, "password": "newsecret"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
