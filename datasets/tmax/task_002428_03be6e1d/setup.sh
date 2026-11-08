#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang openssh-client
    pip3 install pytest cryptography

    mkdir -p /home/user/data
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /tmp/setup_legacy.py
import os
import binascii
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Old insecure key as defined in task
old_key = b"32-byte-old-insecure-key-1234567"
aesgcm = AESGCM(old_key)

# The payload with some IPv4 addresses
plaintext = b"Log start: Connection from 192.168.1.50 failed. SSH key loaded. Server 10.0.0.5 active. Malicious traffic from 203.0.113.42 dropped. End log."

# Generate 12-byte nonce
nonce = os.urandom(12)
ciphertext = aesgcm.encrypt(nonce, plaintext, None)

# Write hex encoded (nonce + ciphertext) to file
with open('/home/user/data/legacy.enc', 'wb') as f:
    f.write(binascii.hexlify(nonce + ciphertext))
EOF

    python3 /tmp/setup_legacy.py
    rm /tmp/setup_legacy.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
