#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import os

def xor_crypt(text: bytes, key: bytes) -> str:
    return bytes([c ^ key[i % len(key)] for i, c in enumerate(text)]).hex()

events = [
    {"pid": 1001, "cmdline": f"/opt/agent --payload {xor_crypt(b'AUTH_TOKEN:ADMIN_9921_XYZ', b'secr')}", "dest_ip": "10.55.1.9"},
    {"pid": 1002, "cmdline": f"/opt/agent --payload {xor_crypt(b'AUTH_TOKEN:USER_1234_ABC', b'pass')}", "dest_ip": "192.168.1.100"},
    {"pid": 1003, "cmdline": f"/opt/agent --payload {xor_crypt(b'AUTH_TOKEN:ADMIN_7777_QWE', b'hack')}", "dest_ip": "172.16.0.50"},
    {"pid": 1004, "cmdline": f"/opt/agent --payload {xor_crypt(b'AUTH_TOKEN:USER_9999_ZZZ', b'word')}", "dest_ip": "10.0.0.5"},
    {"pid": 1005, "cmdline": f"/opt/agent --payload {xor_crypt(b'AUTH_TOKEN:ADMIN_1111_LMN', b'xray')}", "dest_ip": "10.2.3.4"}
]

with open('/home/user/audit_events.log', 'w') as f:
    for event in events:
        f.write(json.dumps(event) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
