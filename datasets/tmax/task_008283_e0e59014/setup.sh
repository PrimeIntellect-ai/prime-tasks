#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

plaintext = b"GET / HTTP/1.1\r\nHost: c2.malicious.local\r\nUser-Agent: curl/7.68.0\r\nX-Exfil-Auth: zK9#mP2@qL5_vX\r\nAccept: */*\r\n\r\n"
pin = 4281

key_val = pin * 1337
key_bytes = key_val.to_bytes(4, byteorder='big')

ciphertext = bytearray()
for i, b in enumerate(plaintext):
    ciphertext.append(b ^ key_bytes[i % 4])

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/exfil.enc', 'wb') as f:
    f.write(ciphertext)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
