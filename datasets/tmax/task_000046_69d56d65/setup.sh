#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import json
from datetime import datetime, timedelta

data = [
    {"timestamp": "2023-10-01T10:15:00", "server_id": "srv-1", "role": "web", "ip_address": "10.0.0.5", "config_val": 100},
    {"timestamp": "2023-10-01T13:45:00", "server_id": "srv-1", "role": "web", "ip_address": "10.0.0.5", "config_val": 150},
    {"timestamp": "2023-10-01T11:20:00", "server_id": "srv-2", "role": "db", "ip_address": "10.0.1.12", "config_val": 500},
    {"timestamp": "2023-10-01T14:10:00", "server_id": "srv-2", "role": "db", "ip_address": "10.0.1.12", "config_val": 550},
    {"timestamp": "2023-10-01T10:05:00", "server_id": "srv-3", "role": "web", "ip_address": "10.0.0.6", "config_val": 110},
    {"timestamp": "2023-10-01T11:00:00", "server_id": "srv-3", "role": "web", "ip_address": "10.0.0.6", "config_val": 120},
    {"timestamp": "2023-10-01T12:30:00", "server_id": "srv-4", "role": "cache", "ip_address": "10.0.2.20", "config_val": 300},
    {"timestamp": "2023-10-01T15:30:00", "server_id": "srv-4", "role": "cache", "ip_address": "10.0.2.20", "config_val": 350}
]

with open("/home/user/config_changes.jsonl", "w") as f:
    for row in data:
        f.write(json.dumps(row) + "\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
