#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import base64
import os

data = [
    {
        "ip": "10.0.0.10",
        "method": "GET",
        "path": "/index.html",
        "headers": {
            "User-Agent": "Mozilla/5.0",
            "Cookie": "session=" + base64.b64encode(b'{"user":"alice","role":"user"}').decode()
        }
    },
    {
        "ip": "10.0.0.11",
        "method": "GET",
        "path": "/download.php?file=../../../../etc/passwd",
        "headers": {
            "User-Agent": "curl/7.68.0",
            "Cookie": "session=" + base64.b64encode(b'{"user":"bob","role":"guest"}').decode()
        }
    },
    {
        "ip": "10.0.0.12",
        "method": "POST",
        "path": "/api/upload",
        "headers": {
            "User-Agent": "Mozilla/5.0",
            "Cookie": "session=" + base64.b64encode(b'{"user":"charlie","role":"admin"}').decode()
        }
    },
    {
        "ip": "10.0.0.13",
        "method": "GET",
        "path": "/assets/%2E%2E%2F%2E%2E%2Fconfig.yml",
        "headers": {
            "User-Agent": "Scanner/1.0",
            "Cookie": "session=" + base64.b64encode(b'{"user":"hacker","role":"administrator"}').decode()
        }
    },
    {
        "ip": "10.0.0.14",
        "method": "GET",
        "path": "/home",
        "headers": {
            "User-Agent": "Mozilla/5.0",
            "Cookie": "session=invalid_base64_data^&*"
        }
    }
]

with open('/home/user/http_traffic.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
