#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    echo "SECRET_RED_TEAM_FLAG_{BYPASS_SUCCESS}" > /home/user/flag.txt
    chmod 400 /home/user/flag.txt

    cat << 'EOF' > /home/user/app/waf.py
import re

def inspect(payload_bytes):
    # WAF pattern matching rules
    # Blocks exact string 'flag'
    if b'flag' in payload_bytes:
        return False
    # Blocks directory traversal attempts
    if b'../' in payload_bytes or b'..\\' in payload_bytes:
        return False
    # Blocks the word 'user'
    if b'user' in payload_bytes:
        return False
    return True
EOF

    # Compile to pyc and remove the source
    python3 -m py_compile /home/user/app/waf.py
    mv /home/user/app/__pycache__/waf.*.pyc /home/user/app/waf.pyc
    rm /home/user/app/waf.py

    cat << 'EOF' > /home/user/app/server.py
import sys
import os

# Load the WAF
sys.path.append('/home/user/app')
import waf

def process_request(payload_file):
    if not os.path.exists(payload_file):
        print("Payload file not found.")
        sys.exit(1)

    with open(payload_file, 'rb') as f:
        data = f.read()

    # Intrusion Detection System check
    if not waf.inspect(data):
        print("WAF Blocked Request: Intrusion Detected!")
        sys.exit(1)

    # Decode payload
    try:
        decoded_path = data.decode('unicode_escape')
    except Exception as e:
        print("Decoding error.")
        sys.exit(1)

    # Vulnerability: LFI
    try:
        with open(decoded_path, 'r') as f:
            content = f.read()
            with open('/home/user/exfiltrated.txt', 'w') as out:
                out.write(content)
        print("Success. Data extracted.")
    except Exception as e:
        print(f"Error reading target file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 server.py <payload_file>")
        sys.exit(1)
    process_request(sys.argv[1])
EOF

    chmod 755 /home/user/app/server.py
    chmod -R 777 /home/user
