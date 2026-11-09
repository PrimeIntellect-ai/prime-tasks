#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib

# Ground truth parameters
K0 = 42
A = 17
C = 105

plaintext = b"TELE_CRITICAL_SYSTEM_ALERT_FLAG{lcg_stream_broken_1337}"

# Calculate checksum
checksum = hashlib.sha256(plaintext).digest()

# Encrypt
encrypted = bytearray()
k = K0
for b in plaintext:
    encrypted.append(b ^ k)
    k = (A * k + C) % 256

# Write to file
with open("/home/user/traffic.bin", "wb") as f:
    f.write(checksum + encrypted)

# Ensure the correct permissions
os.chmod("/home/user/traffic.bin", 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
