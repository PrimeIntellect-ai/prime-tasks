#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_logs.py
import json

logs = [
    {"time": "2023-10-14T12:00:01Z", "client": "192.168.1.101", "request": "/api/v1/users", "status": 200, "user_agent": "Mozilla"},
    {"time": "2023-10-14T12:01:15Z", "client": "10.0.0.5", "request": "/api/v1/auth", "status": 401, "user_agent": "curl/7.68.0"},
    {"time": "2023-10-14T12:02:33Z", "client": "192.168.1.102", "request": "/api/v1/data", "status": 200, "user_agent": "Mozilla"},
    {"time": "2023-10-14T12:03:05Z", "client": "172.16.0.4", "request": "/admin/config", "status": 403, "user_agent": "Python-urllib"},
    {"time": "2023-10-14T12:04:50Z", "client": "10.0.0.8", "request": "/api/v1/missing", "status": 404, "user_agent": "curl"},
    {"time": "2023-10-14T12:05:10Z", "client": "192.168.1.105", "request": "/api/v1/status", "status": 500, "user_agent": "PostmanRuntime/7.28.4"}
]

with open("/home/user/app_logs.raw", "w", encoding="utf-16le") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")
EOF
    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
