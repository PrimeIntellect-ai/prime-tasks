#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access_logs.jsonl
{"source": "ENTRY_PORTAL", "target": "PROXY_A", "weight": 10, "status": "active"}
{"source": "ENTRY_PORTAL", "target": "PROXY_B", "weight": 5, "status": "active"}
{"source": "ENTRY_PORTAL", "target": "SECURE_VAULT", "weight": 1, "status": "stale"}
{"source": "PROXY_A", "target": "DB_RELAY", "weight": 10, "status": "active"}
{"source": "PROXY_B", "target": "DB_RELAY", "weight": 50, "status": "active"}
{"source": "PROXY_B", "target": "CACHE_SERVER", "weight": 8, "status": "active"}
{"source": "CACHE_SERVER", "target": "DB_RELAY", "weight": 5, "status": "active"}
{"source": "DB_RELAY", "target": "SECURE_VAULT", "weight": 10, "status": "active"}
{"source": "PROXY_A", "target": "SECURE_VAULT", "weight": 15, "status": "stale"}
{"source": "CACHE_SERVER", "target": "SECURE_VAULT", "weight": 30, "status": "active"}
EOF

    chmod -R 777 /home/user
