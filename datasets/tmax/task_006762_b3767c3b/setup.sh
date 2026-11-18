#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest --default-timeout=100

mkdir -p /home/user

cat << 'EOF' > /tmp/setup.py
import base64
import json
import itertools
import os

os.makedirs("/home/user", exist_ok=True)

raw_logs = [
    {"csp-report": {"document-uri": "https://company.com/index.html", "blocked-uri": "https://analytics.trusted.com/track.js", "violated-directive": "script-src"}},
    {"csp-report": {"document-uri": "https://company.com/index.html", "blocked-uri": "http://evildomain.com/scripts/malware.js", "violated-directive": "script-src"}},
    {"csp-report": {"document-uri": "https://company.com/about.html", "blocked-uri": "https://cdn.example.org/lib.js", "violated-directive": "script-src"}},
    {"csp-report": {"document-uri": "https://company.com/contact.html", "blocked-uri": "http://10.99.0.55/drop/payload.exe", "violated-directive": "script-src"}},
    {"csp-report": {"document-uri": "https://company.com/dashboard.html", "blocked-uri": "https://analytics.trusted.com/beacon.js", "violated-directive": "script-src"}}
]

plain_text = "\n".join(json.dumps(log) for log in raw_logs)

key = "INTRUSION"
xored = bytes(a ^ ord(b) for a, b in zip(plain_text.encode('utf-8'), itertools.cycle(key)))
encoded = base64.b64encode(xored).decode('utf-8')

with open("/home/user/exfil_logs.enc", "w") as f:
    f.write(encoded)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
