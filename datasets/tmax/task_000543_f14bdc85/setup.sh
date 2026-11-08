#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux sed gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/encrypt.py
#!/usr/bin/env python3
import sys
import binascii

def encrypt(text):
    key = b'S3cr3t'
    res = bytearray()
    for i, c in enumerate(text.encode('utf-8')):
        res.append(c ^ key[i % len(key)])
    return binascii.hexlify(res).decode()

if __name__ == "__main__":
    input_data = sys.stdin.read()
    print(encrypt(input_data), end='')
EOF
    chmod +x /home/user/encrypt.py

    cat << 'EOF' > /home/user/raw.log
Connection received from 192.168.1.100 at midnight.
Failed login attempt from 10.0.0.5 for user admin.
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
