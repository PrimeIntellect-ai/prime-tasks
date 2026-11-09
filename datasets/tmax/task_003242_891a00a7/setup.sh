#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import base64

def encode_b64url(data: dict) -> str:
    s = json.dumps(data, separators=(',', ':')).encode('utf-8')
    return base64.urlsafe_b64encode(s).decode('utf-8').rstrip('=')

logs = [
    {"timestamp": "2023-10-01T10:00:00Z", "ip_address": "192.168.1.100", "endpoint": "/api/v1/data", "auth_header": f"Bearer {encode_b64url({'alg': 'HS256', 'typ': 'JWT'})}.{encode_b64url({'user_id': 'alice', 'role': 'user'})}.valid_signature"},
    {"timestamp": "2023-10-01T10:05:12Z", "ip_address": "10.0.0.5", "endpoint": "/api/v1/admin", "auth_header": f"Bearer {encode_b64url({'alg': 'none', 'typ': 'JWT'})}.{encode_b64url({'user_id': 'admin', 'role': 'admin'})}."},
    {"timestamp": "2023-10-01T10:06:00Z", "ip_address": "172.16.0.4", "endpoint": "/api/v1/profile", "auth_header": f"Bearer {encode_b64url({'alg': 'NONE', 'typ': 'JWT'})}.{encode_b64url({'user_id': 'bob', 'role': 'user'})}."},
    {"timestamp": "2023-10-01T10:10:00Z", "ip_address": "192.168.1.101", "endpoint": "/api/v1/data", "auth_header": "Bearer invalid_token_format"},
    {"timestamp": "2023-10-01T10:15:22Z", "ip_address": "10.0.0.99", "endpoint": "/api/v1/settings", "auth_header": f"Bearer {encode_b64url({'alg': 'None', 'typ': 'JWT'})}.{encode_b64url({'user_id': 'charlie', 'role': 'admin'})}.xyz123"}
]

with open("/home/user/api_logs.jsonl", "w") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
