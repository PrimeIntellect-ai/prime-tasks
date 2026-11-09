#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/verify.py
import sys
import os
import json
import base64

def b64_decode(data):
    padding = '=' * (4 - (len(data) % 4))
    return base64.urlsafe_b64decode(data + padding).decode('utf-8')

def verify(file_path):
    if not os.path.exists(file_path):
        print("Error: File not found.")
        sys.exit(1)

    stat = os.stat(file_path)
    if oct(stat.st_mode)[-3:] != '400':
        print("Error: Insecure file permissions. Must be 0400.")
        sys.exit(1)

    with open(file_path, 'r') as f:
        token = f.read().strip()

    parts = token.split('.')
    if len(parts) != 3:
        print("Error: Invalid token format. Expected Header.Payload.Signature")
        sys.exit(1)

    try:
        header = json.loads(b64_decode(parts[0]))
        payload = json.loads(b64_decode(parts[1]))
    except Exception as e:
        print("Error: Invalid JSON encoding.")
        sys.exit(1)

    signature = parts[2]

    alg = header.get("alg", "").lower()
    if alg != "none":
        # Fake signature validation for any other algorithm
        if signature != "valid_sig_for_strong_crypto":
            print("Error: Invalid signature.")
            sys.exit(1)
    elif alg == "none":
        # When alg is none, signature should be empty
        if signature != "":
            print("Error: Signature must be empty when alg is none.")
            sys.exit(1)

    if payload.get("admin") is True:
        print("Access granted: admin")
        sys.exit(0)
    else:
        print("Access denied: regular user")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python verify.py <token_file>")
        sys.exit(1)
    verify(sys.argv[1])
EOF
    chmod +x /home/user/verify.py

    chmod -R 777 /home/user
