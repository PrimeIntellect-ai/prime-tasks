#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import hmac
import hashlib
import base64
import json
import os

os.makedirs('/home/user', exist_ok=True)

secret_key = b"super_secret_audit_key_2024"
with open("/home/user/.secret_key", "wb") as f:
    f.write(secret_key)

logs = [
    {"ip": "192.168.1.10", "ts": "1700000000", "payload": '{"user": "alice", "cc": "1111-2222-3333-4444"}', "valid": True},
    {"ip": "10.0.0.5", "ts": "1700000010", "payload": '{"user": "bob", "cc": "5555-6666-7777-8888"}', "valid": False},
    {"ip": "192.168.1.12", "ts": "1700000020", "payload": '{"user": "charlie", "cc": "9999-0000-1111-2222"}', "valid": True},
    {"ip": "10.0.0.6", "ts": "1700000030", "payload": '{"user": "eve", "cc": "3333-4444-5555-6666"}', "valid": False}
]

with open("/home/user/raw_access.log", "w") as f:
    for log in logs:
        b64_payload = base64.b64encode(log["payload"].encode()).decode()
        msg = f"{log['ip']}|{log['ts']}|{b64_payload}".encode()

        if log["valid"]:
            token = hmac.new(secret_key, msg, hashlib.sha256).hexdigest()
        else:
            token = hmac.new(b"wrong_key", msg, hashlib.sha256).hexdigest()

        f.write(f"{log['ip']}|{log['ts']}|{token}|{b64_payload}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
    chmod 600 /home/user/.secret_key
    chmod 644 /home/user/raw_access.log
