#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

logs = [
    '{"timestamp": "2023-10-01T10:00:01Z", "endpoint": "/api/users", "response_time_ms": 100, "user_agent": "Mozilla/5.0"}',
    '{"timestamp": "2023-10-01T10:00:02Z", "endpoint": "/api/users", "response_time_ms": 105, "user_agent": "Chrome\\u002X"}',
    '{"timestamp": "2023-10-01T10:00:03Z", "endpoint": "/api/users", "response_time_ms": 95, "user_agent": "Safari"}',
    '{"timestamp": "2023-10-01T10:00:04Z", "endpoint": "/api/users", "response_time_ms": 110, "user_agent": "Edge\\u123Z"}',
    '{"timestamp": "2023-10-01T10:00:05Z", "endpoint": "/api/users", "response_time_ms": 100, "user_agent": "Mozilla/5.0"}',
    '{"timestamp": "2023-10-01T10:00:06Z", "endpoint": "/api/users", "response_time_ms": 450, "user_agent": "BadBot"}',
    '{"timestamp": "2023-10-01T10:00:07Z", "endpoint": "/api/users", "response_time_ms": 105, "user_agent": "Chrome"}',

    '{"timestamp": "2023-10-01T10:00:01Z", "endpoint": "/api/auth", "response_time_ms": 50, "user_agent": "Mozilla"}',
    '{"timestamp": "2023-10-01T10:00:02Z", "endpoint": "/api/auth", "response_time_ms": 52, "user_agent": "Chrome\\uGGGG"}',
    '{"timestamp": "2023-10-01T10:00:03Z", "endpoint": "/api/auth", "response_time_ms": 48, "user_agent": "Safari"}',
    '{"timestamp": "2023-10-01T10:00:04Z", "endpoint": "/api/auth", "response_time_ms": 51, "user_agent": "Edge"}',
    '{"timestamp": "2023-10-01T10:00:05Z", "endpoint": "/api/auth", "response_time_ms": 49, "user_agent": "Mozilla"}',
    '{"timestamp": "2023-10-01T10:00:06Z", "endpoint": "/api/auth", "response_time_ms": 60, "user_agent": "Curl"}',
    '{"timestamp": "2023-10-01T10:00:07Z", "endpoint": "/api/auth", "response_time_ms": 200, "user_agent": "Python"}',
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/app_logs.jsonl", "w") as f:
    for line in logs:
        f.write(line + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
