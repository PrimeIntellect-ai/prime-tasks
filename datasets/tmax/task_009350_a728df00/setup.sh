#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography PyJWT

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

# Data to encrypt
pin = "6194"
plaintext = json.dumps({"endpoint": "/api/v1/escalate", "role_required": "system_admin"}).encode('utf-8')

# PKCS7 padding
pad_len = 16 - (len(plaintext) % 16)
plaintext_padded = plaintext + bytes([pad_len] * pad_len)

# Cryptographic parameters
key = hashlib.sha256(pin.encode('utf-8')).digest()
iv = b"abcdefghijklmnop" # 16 bytes IV

# Encrypt
cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
encryptor = cipher.encryptor()
ciphertext = encryptor.update(plaintext_padded) + encryptor.finalize()

# Write to file
with open("/home/user/intercepted_data.bin", "wb") as f:
    f.write(iv + ciphertext)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
