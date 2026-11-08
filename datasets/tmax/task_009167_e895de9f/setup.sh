#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ssh_audit
    mkdir -p /home/user/artifacts
    mkdir -p /home/user/auth

    # Phase 1: SSH Keys
    ssh-keygen -t rsa -b 1024 -f /home/user/ssh_audit/id_rsa_1024 -N "" -q
    ssh-keygen -t rsa -b 4096 -f /home/user/ssh_audit/id_rsa_4096 -N "" -q
    ssh-keygen -t ed25519 -f /home/user/ssh_audit/id_ed25519_open -N "" -q
    chmod 0644 /home/user/ssh_audit/id_ed25519_open
    ssh-keygen -t ecdsa -b 256 -f /home/user/ssh_audit/id_ecdsa_256 -N "" -q

    # Phase 2: Artifacts
    head -c 1024 /dev/urandom > /home/user/artifacts/app_v1.bin
    head -c 1024 /dev/urandom > /home/user/artifacts/lib_v1.bin
    head -c 1024 /dev/urandom > /home/user/artifacts/config_v1.bin
    head -c 1024 /dev/urandom > /home/user/artifacts/data_v1.bin

    cd /home/user/artifacts
    sha256sum *.bin > manifest.sha256

    # Tamper with two of them
    echo "tampered" >> /home/user/artifacts/lib_v1.bin
    echo "tampered" >> /home/user/artifacts/data_v1.bin

    # Phase 3: Auth Flow
    cd /home/user/auth
    echo "super_secret_production_key_99" > secret.key
    chmod 0644 secret.key

    cat << 'EOF' > login_check.py
import hmac
import hashlib
import json
import os
import sys

key_path = 'secret.key'
stat_info = os.stat(key_path)
if oct(stat_info.st_mode)[-3:] != '600':
    print("ERROR: Insecure permissions on secret.key. Must be 0600.")
    sys.exit(1)

with open(key_path, 'r') as f:
    secret = f.read().strip().encode()

with open('requests.json', 'r') as f:
    data = json.load(f)

for req in data:
    expected_mac = hmac.new(secret, req['payload'].encode(), hashlib.md5).hexdigest()
    if expected_mac == req['signature']:
        print(req['user'])
EOF

    cat << 'EOF' > generate_requests.py
import hmac
import hashlib
import json

secret = b"super_secret_production_key_99"

requests = []
users = ["alice", "bob", "charlie", "dave"]
payloads = ["login_1", "login_2", "login_3", "login_4"]

for u, p in zip(users, payloads):
    # Only charlie gets the CORRECT SHA256 signature
    if u == "charlie":
        sig = hmac.new(secret, p.encode(), hashlib.sha256).hexdigest()
    else:
        # Others get invalid or md5 signatures
        sig = hmac.new(secret, p.encode(), hashlib.md5).hexdigest()

    requests.append({"user": u, "payload": p, "signature": sig})

with open("requests.json", "w") as f:
    json.dump(requests, f)
EOF

    python3 generate_requests.py
    rm generate_requests.py

    chmod -R 777 /home/user
