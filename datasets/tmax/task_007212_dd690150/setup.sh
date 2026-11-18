#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

def encrypt(plaintext, seed):
    key = seed
    ciphertext = bytearray([seed])
    for char in plaintext:
        key = (key * 13 + 11) % 256
        ciphertext.append(ord(char) ^ key)
    return ciphertext.hex()

logs = [
    f"2023-10-25 10:15:02 | 192.168.1.50 | {encrypt('MAGIC_C2_REQ:PING', 42)}",
    f"2023-10-25 10:15:05 | 192.168.1.51 | {encrypt('MAGIC_C2_REQ:STATUS', 128)}",
    f"2023-10-25 10:15:09 | 10.0.0.5 | {encrypt('MAGIC_C2_REQ:INFO', 255)}"
]

with open("/home/user/c2_logs.txt", "w") as f:
    for log in logs:
        f.write(log + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
