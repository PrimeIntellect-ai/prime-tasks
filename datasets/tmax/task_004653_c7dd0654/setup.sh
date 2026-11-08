#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import json
import base64
import hmac
import hashlib

SECRET = b"my_super_secret_key_123"

def make_token(username, valid=True):
    payload = json.dumps({"username": username}).encode()
    b64_payload = base64.urlsafe_b64encode(payload).rstrip(b'=')

    key = SECRET if valid else b"wrong_key"
    sig = hmac.new(key, b64_payload, hashlib.sha256).digest()
    b64_sig = base64.urlsafe_b64encode(sig).rstrip(b'=')

    return f"{b64_payload.decode()}.{b64_sig.decode()}"

logs = [
    {"timestamp": "2023-10-01T10:00:00Z", "ip": "10.0.0.1", "method": "POST", "path": "/upload", "headers": {"Cookie": f"session={make_token('alice', True)}", "X-Upload-Path": "images/"}},
    # Malicious, valid token -> should be found
    {"timestamp": "2023-10-01T10:01:00Z", "ip": "10.0.0.2", "method": "POST", "path": "/upload?dir=../../etc", "headers": {"Cookie": f"session={make_token('bob', True)}"}},
    # Malicious, invalid token -> ignore
    {"timestamp": "2023-10-01T10:02:00Z", "ip": "10.0.0.3", "method": "POST", "path": "/upload", "headers": {"Cookie": f"session={make_token('eve', False)}", "X-Upload-Path": "..\\windows\\system32"}},
    # Malicious header, valid token -> should be found
    {"timestamp": "2023-10-01T10:03:00Z", "ip": "10.0.0.4", "method": "POST", "path": "/upload", "headers": {"Cookie": f"session={make_token('charlie', True)}; theme=dark", "X-Upload-Path": "%2e%2e%2fetc/passwd"}},
    # Malicious path, valid token -> should be found
    {"timestamp": "2023-10-01T10:04:00Z", "ip": "10.0.0.5", "method": "POST", "path": "/download/%2E%2E%5Cconfig", "headers": {"Cookie": f"session={make_token('dave', True)}"}},
    # Benign -> ignore
    {"timestamp": "2023-10-01T10:05:00Z", "ip": "10.0.0.6", "method": "GET", "path": "/index.html", "headers": {}}
]

with open("/home/user/server.log", "w") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")

with open("/home/user/secret.key", "w") as f:
    f.write("my_super_secret_key_123")
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
