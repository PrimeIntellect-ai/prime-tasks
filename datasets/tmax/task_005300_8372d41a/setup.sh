#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/upload.py
import sys
import os

if len(sys.argv) != 3:
    print("Usage: python upload.py <filename> <content>")
    sys.exit(1)

filename = sys.argv[1]
content = sys.argv[2]
base_dir = "/home/user/uploads"

# Vulnerable: No sanitization of 'filename'
filepath = os.path.join(base_dir, filename)

with open(filepath, 'w') as f:
    f.write(content)
print(f"File saved to {filepath}")
EOF
    chmod +x /home/user/upload.py

    echo "malicious_payload_123" > /home/user/suspicious_bin

    echo "ssh-rsa AAAAB3NzaC1yc2E... attacker@evil.com" > /home/user/.ssh/authorized_keys

    chmod -R 777 /home/user
