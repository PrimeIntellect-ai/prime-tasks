#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import os

data = [
    {
        "ip": "192.168.1.50",
        "headers": {
            "Content-Type": "application/json",
            "Set-Cookie": "session_id=abc1234; HttpOnly",
            "Authorization": "Bearer token123_secret"
        }
    },
    {
        "ip": "10.0.0.5",
        "headers": {
            "Content-Type": "text/html",
            "Set-Cookie": "track_id=xyz987; Secure; HttpOnly",
            "X-Frame-Options": "DENY"
        }
    },
    {
        "ip": "172.16.0.10",
        "headers": {
            "Set-Cookie": "auth_token=super_secret_value",
            "Server": "nginx"
        }
    },
    {
        "ip": "192.168.1.50",
        "headers": {
            "Set-Cookie": "legacy_id=111; secure",
            "Authorization": "Basic dXNlcjpwYXNz"
        }
    }
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/traffic.json", "w") as f:
    json.dump(data, f, indent=2)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
