#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq parallel gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import json

lines = [
    {"id": "1", "ip": "10.0.0.1", "message": r"Error in module A \u1234"},
    {"id": "2", "ip": "10.0.0.2", "message": r"Error in module B \uGHIJ"},
    {"id": "3", "ip": "10.0.0.3", "message": r"Error in module C \u0000"},
    {"id": "4", "ip": "10.0.0.4", "message": r"Error in module B \uGHIJ"}, # Duplicate message
    {"id": "5", "ip": "192.168.1.5", "message": r"Crash dump \uX999 details"},
    {"id": "6", "ip": "192.168.1.5", "message": r"Crash dump \uX999 details"}, # Duplicate message
    {"id": "7", "ip": "172.16.0.7", "message": r"Valid hex \uABCD but bad string \uQQQQ"}
]

with open("/home/user/corrupt_logs.jsonl", "w") as f:
    for line in lines:
        # Write raw strings to ensure literal \u is preserved, not parsed by python
        f.write('{"id": "' + line["id"] + '", "ip": "' + line["ip"] + '", "message": "' + line["message"] + '"}\n')
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
