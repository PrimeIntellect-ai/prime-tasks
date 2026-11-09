#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/events.jsonl
{"user_id": 101, "event_type": "query", "timestamp": "2023-01-01T10:00:00Z", "metadata": {"duration": 150.5, "status": "success"}}
{"user_id": 101, "event_type": "query", "timestamp": "2023-01-01T10:05:00Z", "metadata": {"duration": 200.0, "status": "success"}}
{"user_id": 101, "event_type": "click", "timestamp": "2023-01-01T10:06:00Z", "metadata": {"duration": 10.0, "status": "success"}}
{"user_id": 102, "event_type": "query", "timestamp": "2023-01-01T10:07:00Z", "metadata": {"duration": 300.25, "status": "success"}}
{"user_id": 102, "event_type": "query", "timestamp": "2023-01-01T10:08:00Z", "metadata": {"duration": 500.0, "status": "error"}}
{"user_id": 103, "event_type": "query", "timestamp": "2023-01-01T10:10:00Z", "metadata": {"duration": 45.1, "status": "success"}}
{"user_id": 103, "event_type": "query", "timestamp": "2023-01-01T10:11:00Z", "metadata": {"duration": 45.1, "status": "success"}}
{"user_id": 104, "event_type": "query", "timestamp": "2023-01-01T10:15:00Z", "metadata": {"duration": 300.25, "status": "success"}}
EOF

    chmod -R 777 /home/user
