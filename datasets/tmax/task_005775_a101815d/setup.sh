#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import json
import base64
import urllib.parse
import os

def encode_payload(payload):
    b64 = base64.b64encode(payload.encode('utf-8')).decode('utf-8')
    return urllib.parse.quote(b64)

logs = [
    {
        "source_ip": "192.168.1.10",
        "method": "GET",
        "headers": {"User-Agent": "Mozilla/5.0"},
        "cookies": {"session": "12345", "X-Debug-Session": encode_payload("print('hello world')")}
    },
    {
        "source_ip": "10.0.5.22",
        "method": "POST",
        "headers": {"User-Agent": "curl/7.68.0"},
        "cookies": {"X-Debug-Session": encode_payload("import os\nos.system('whoami')")}
    },
    {
        "source_ip": "172.16.0.4",
        "method": "GET",
        "headers": {"User-Agent": "Mozilla/5.0"},
        "cookies": {"X-Debug-Session": encode_payload("import sys\nprint(sys.version)")}
    },
    {
        "source_ip": "203.0.113.8",
        "method": "POST",
        "headers": {"User-Agent": "python-requests/2.25.1"},
        "cookies": {"X-Debug-Session": encode_payload("x = 'bad'\nexec('print(x)')")}
    },
    {
        "source_ip": "198.51.100.14",
        "method": "GET",
        "headers": {"User-Agent": "Mozilla/5.0"},
        "cookies": {"X-Debug-Session": encode_payload("from subprocess import Popen\nPopen(['ls', '-l'])")}
    },
    {
        "source_ip": "192.168.1.10",
        "method": "GET",
        "headers": {"User-Agent": "Mozilla/5.0"},
        "cookies": {"X-Debug-Session": encode_payload("eval('1+1')")}
    }
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/traffic_logs.json", "w") as f:
    json.dump(logs, f, indent=4)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
