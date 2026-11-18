#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user/evidence', exist_ok=True)

key = b'hack'
c2_ip = bytes([192, 168, 137, 42])
c2_port = struct.pack('!H', 4444)

plain = (
    b'\x7FELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' + 
    b'A' * 50 + 
    b'C2_START' + 
    c2_ip + 
    c2_port + 
    b'B' * 20
)

enc = bytes([plain[i] ^ key[i % 4] for i in range(len(plain))])

with open('/home/user/evidence/payload.enc', 'wb') as f:
    f.write(enc)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
