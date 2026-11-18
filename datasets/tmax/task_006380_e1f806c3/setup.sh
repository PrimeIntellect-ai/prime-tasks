#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang openssl
    pip3 install pytest PyJWT cryptography

    mkdir -p /home/user/certs
    cd /home/user/certs

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/CN=Test CA"

    # Generate Server Key and CSR
    openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/CN=Test Server"

    # Sign Server Cert with CA
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

    # Generate a rogue key for invalid signature tests
    openssl genrsa -out rogue.key 2048

    cd /home/user

    # Create python script to generate JWTs using PyJWT
    cat << 'EOF' > generate_logs.py
import jwt
import json
import time

with open('certs/server.key', 'r') as f:
    private_key = f.read()

with open('certs/rogue.key', 'r') as f:
    rogue_key = f.read()

# Valid Token
valid_token = jwt.encode({"sub": "user1", "exp": int(time.time()) + 3600}, private_key, algorithm="RS256")

# Invalid Signature Token
invalid_sig_token = jwt.encode({"sub": "user2", "exp": int(time.time()) + 3600}, rogue_key, algorithm="RS256")

# Expired Token
expired_token = jwt.encode({"sub": "user3", "exp": int(time.time()) - 3600}, private_key, algorithm="RS256")

logs = [
    {"ip": "192.168.1.10", "endpoint": "/api/data", "token": valid_token},
    {"ip": "10.0.0.5", "endpoint": "/api/admin", "token": invalid_sig_token},
    {"ip": "192.168.1.11", "endpoint": "/api/users", "token": valid_token},
    {"ip": "172.16.0.8", "endpoint": "/api/config", "token": expired_token}
]

with open('raw_logs.jsonl', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')
EOF

    python3 generate_logs.py
    rm generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
