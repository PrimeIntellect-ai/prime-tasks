#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create wordlist
    cat << 'EOF' > /home/user/wordlist.txt
admin
password
qwerty
123456
secret123
supersecret
compliance
EOF

    # Create setup script for requests.json
    cat << 'EOF' > /tmp/setup_jwt.py
import json
import base64
import hmac
import hashlib

def base64url_encode(data):
    return base64.urlsafe_b64encode(data).replace(b'=', b'').decode('utf-8')

# Valid token setup
header_valid = {"alg": "HS256", "typ": "JWT"}
payload_valid = {"username": "alice", "role": "user"}

enc_header_v = base64url_encode(json.dumps(header_valid).encode('utf-8'))
enc_payload_v = base64url_encode(json.dumps(payload_valid).encode('utf-8'))

secret = b"secret123"
signature = base64url_encode(hmac.new(secret, f"{enc_header_v}.{enc_payload_v}".encode('utf-8'), hashlib.sha256).digest())
jwt_valid = f"{enc_header_v}.{enc_payload_v}.{signature}"

# Alg=none token setup
header_none = {"alg": "none", "typ": "JWT"}
payload_none = {"username": "hacker_bob", "role": "admin"}

enc_header_n = base64url_encode(json.dumps(header_none).encode('utf-8'))
enc_payload_n = base64url_encode(json.dumps(payload_none).encode('utf-8'))

jwt_none = f"{enc_header_n}.{enc_payload_n}."

logs = [
    {
        "ip": "192.168.1.10",
        "method": "GET",
        "path": "/api/data",
        "authorization": f"Bearer {jwt_valid}"
    },
    {
        "ip": "10.0.0.5",
        "method": "POST",
        "path": "/api/admin",
        "authorization": f"Bearer {jwt_none}"
    }
]

with open('/home/user/requests.json', 'w') as f:
    json.dump(logs, f, indent=2)
EOF

    # Run setup script
    python3 /tmp/setup_jwt.py
    rm /tmp/setup_jwt.py

    # Create TLS certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/server.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=InternalCorp"
    rm -f /tmp/key.pem

    chmod -R 777 /home/user
