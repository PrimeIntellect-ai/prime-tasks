#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/setup_data.py
import json

data = [
    # Endpoint A
    {"timestamp": 100, "endpoint": "/api/v1/users", "status_code": 200, "response_time_ms": 50, "request_payload": "user=1"},
    {"timestamp": 101, "endpoint": "/api/v1/users", "status_code": 200, "response_time_ms": 52, "request_payload": "user=2"},
    {"timestamp": 102, "endpoint": "/api/v1/users", "status_code": 200, "response_time_ms": 48, "request_payload": "user=3"},
    # Duplicate payload, later timestamp -> should be discarded
    {"timestamp": 103, "endpoint": "/api/v1/users", "status_code": 200, "response_time_ms": 45, "request_payload": "user=2"},
    {"timestamp": 104, "endpoint": "/api/v1/users", "status_code": 200, "response_time_ms": 55, "request_payload": "user=4"},
    # Invalid status code -> should be discarded
    {"timestamp": 105, "endpoint": "/api/v1/users", "status_code": 999, "response_time_ms": 50, "request_payload": "user=5"},
    {"timestamp": 106, "endpoint": "/api/v1/users", "status_code": 200, "response_time_ms": 51, "request_payload": "user=6"},
    # Anomaly
    {"timestamp": 107, "endpoint": "/api/v1/users", "status_code": 500, "response_time_ms": 150, "request_payload": "user=7"},

    # Endpoint B
    {"timestamp": 200, "endpoint": "/api/v2/items", "status_code": 201, "response_time_ms": 10, "request_payload": "item=A"},
    # Invalid response time -> discard
    {"timestamp": 201, "endpoint": "/api/v2/items", "status_code": 201, "response_time_ms": -5, "request_payload": "item=B"},
    {"timestamp": 202, "endpoint": "/api/v2/items", "status_code": 404, "response_time_ms": 12, "request_payload": "item=C"},
    # Anomaly
    {"timestamp": 203, "endpoint": "/api/v2/items", "status_code": 503, "response_time_ms": 40, "request_payload": "item=D"}
]

with open('/home/user/logs/raw_requests.jsonl', 'w') as f:
    for d in data:
        f.write(json.dumps(d) + '\n')
EOF
    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
