#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import json

os.makedirs("/home/user", exist_ok=True)

data = [
    # Valid logs
    {"timestamp": "2023-10-01T10:00:00Z", "ip_address": "10.0.0.5", "user_email": "alice@example.com", "endpoint": "/home", "status": 200},
    {"timestamp": "2023-10-01T10:01:00Z", "ip_address": "10.0.0.5", "user_email": "alice@example.com", "endpoint": "/profile", "status": 200},
    {"timestamp": "2023-10-01T10:02:00Z", "ip_address": "192.168.1.50", "user_email": "bob@example.com", "endpoint": "/home", "status": 200},
    {"timestamp": "2023-10-01T10:03:00Z", "ip_address": "192.168.1.50", "user_email": "bob@example.com", "endpoint": "/settings", "status": 200},
    {"timestamp": "2023-10-01T10:04:00Z", "ip_address": "192.168.1.50", "user_email": "bob@example.com", "endpoint": "/profile", "status": 200},
    {"timestamp": "2023-10-01T10:05:00Z", "ip_address": "10.1.2.3", "user_email": "charlie@example.com", "endpoint": "/home", "status": 200},
    {"timestamp": "2023-10-01T10:06:00Z", "ip_address": "10.1.2.3", "user_email": "charlie@example.com", "endpoint": "/settings", "status": 403},

    # Very similar to bob
    {"timestamp": "2023-10-01T10:07:00Z", "ip_address": "172.16.0.100", "user_email": "dave@example.com", "endpoint": "/home", "status": 200},
    {"timestamp": "2023-10-01T10:08:00Z", "ip_address": "172.16.0.100", "user_email": "dave@example.com", "endpoint": "/settings", "status": 200},
    {"timestamp": "2023-10-01T10:09:00Z", "ip_address": "172.16.0.100", "user_email": "dave@example.com", "endpoint": "/profile", "status": 200},
    {"timestamp": "2023-10-01T10:10:00Z", "ip_address": "172.16.0.100", "user_email": "dave@example.com", "endpoint": "/billing", "status": 200},

    # Invalid logs
    {"timestamp": "2023-10-01T10:11:00Z", "ip_address": "10.0.0.5", "endpoint": "/home", "status": 200}, # missing user_email
    {"timestamp": "2023-10-01T10:12:00Z", "ip_address": "10.0.0.5", "user_email": "alice@example.com", "endpoint": "/home", "status": "200"}, # status is string
    {"timestamp": "2023-10-01T10:13:00Z", "ip_address": "10.0.0.5", "user_email": "alice@example.com", "endpoint": "/home", "status": 200, "extra": "data"} # extra field
]

with open("/home/user/raw_logs.jsonl", "w") as f:
    for d in data:
        f.write(json.dumps(d) + "\n")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
