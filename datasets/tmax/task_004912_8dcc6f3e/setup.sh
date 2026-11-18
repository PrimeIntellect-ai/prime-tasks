#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import base64
import zlib
import json
import os

configs = [
    (1672531200, 100), # Baseline
    (1672534800, 100), # No change
    (1672617600, 150), # Change 1: 100 -> 150
    (1672621200, 150), # No change
    (1672704000, 500), # Change 2: 150 -> 500
    (1672790400, 50),  # Change 3: 500 -> 50
    (1672876800, 50)   # No change
]

log_path = '/home/user/config_history.log'
os.makedirs(os.path.dirname(log_path), exist_ok=True)

with open(log_path, 'w') as f:
    for ts, max_conn in configs:
        data = {
            "system": {"version": "1.0.4", "uptime": 34902},
            "database": {"host": "10.0.0.5", "max_connections": max_conn, "timeout": 30}
        }
        json_str = json.dumps(data)
        compressed = zlib.compress(json_str.encode('utf-8'))
        encoded = base64.b64encode(compressed).decode('utf-8')
        f.write(f"{ts} {encoded}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
