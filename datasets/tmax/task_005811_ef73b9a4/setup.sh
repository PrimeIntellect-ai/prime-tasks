#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.py
import json

data = [
    # web-01 sequence
    {"host": "web-01", "timestamp": 1696150000, "cpu_cores": 4, "ram_gb": 16, "max_conns": 100},
    {"host": "web-01", "timestamp": "2023-10-01T08:50:00Z", "cpu_cores": 4, "ram_gb": 16, "max_conns": 100},
    {"host": "web-01", "timestamp": "2023-10-01 03:00:00 -0700", "cpu_cores": 8, "ram_gb": 16, "max_conns": 500},
    {"host": "web-01", "timestamp": 1696158000, "cpu_cores": 8, "ram_gb": 32, "max_conns": 500},

    # db-01 sequence
    {"host": "db-01", "timestamp": "2023-10-02T14:00:00Z", "cpu_cores": 16, "ram_gb": 128, "max_conns": 2000},
    {"host": "db-01", "timestamp": 1696248000, "cpu_cores": 16, "ram_gb": 64, "max_conns": 1000},
    {"host": "db-01", "timestamp": "2023-10-02 09:00:00 -0400", "cpu_cores": 16, "ram_gb": 128, "max_conns": 2000},

    # cache-01 sequence
    {"host": "cache-01", "timestamp": 1696300000, "cpu_cores": 2, "ram_gb": 8, "max_conns": 50},
    {"host": "cache-01", "timestamp": "2023-10-03T02:30:00Z", "cpu_cores": 2, "ram_gb": 8, "max_conns": 100},
]

with open('/home/user/raw_configs.jsonl', 'w') as f:
    for d in data:
        f.write(json.dumps(d) + '\n')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
