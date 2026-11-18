#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

logs = [
    '{"event_id": "1", "timestamp": "2023-10-01T10:15:00Z", "payload": {"user": "alice", "action": "login"}, "response_time": 100.0}\n',
    '{"event_id": "2", "timestamp": "2023-10-01T10:45:00Z", "payload": {"user": "bob", "action": "view"}, "response_time": 200.0}\n',
    '{"event_id": "3", "timestamp": 1696157100, "payload": {"user": "bob", "action": "view"}, "response_time": 250.0}\n',
    '{"event_id": "4", "timestamp": "2023-10-01T11:05:00Z", "payload": {"user": "charlie", "action": "logout"}, "response_time": 150.0}\n',
    '{"event_id": "5", "timestamp": "2023-10-01T11:59:59Z", "payload": {"user": "dave", "action": "login"}, "response_time": 50.0}\n',
    '{"event_id": "6", "timestamp": "2023-10-01T10:00:00Z", "payload": "bad unicode \\u001Z", "response_time": 10.0}\n',
    '{"event_id": "7", "timestamp": "2023-10-01T12:00:00Z", "payload": {"user": "eve", "action": "view"}, "response_time": 300.0}\n',
    '{"event_id": "8", "timestamp": "2023-10-01T12:30:00Z", "payload": {"user": "eve", "action": "view"}, "response_time": 300.0}\n'
]

with open('/home/user/app_logs.jsonl', 'w') as f:
    f.writelines(logs)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
