#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_updates.jsonl
{"timestamp": "2023-11-01T08:12:00", "service": "web", "max_connections": 100}
{"timestamp": "2023-11-01T09:45:00", "service": "db", "max_connections": 50}
{"timestamp": "2023-11-01T11:05:00", "service": "web", "max_connections": 500}
{"timestamp": "2023-11-01T13:30:00", "service": "web", "max_connections": 250}
{"timestamp": "2023-11-01T14:15:00", "service": "web", "max_connections": 800}
{"timestamp": "2023-11-01T16:05:00", "service": "web", "max_connections": 600}
EOF

    chmod -R 777 /home/user
