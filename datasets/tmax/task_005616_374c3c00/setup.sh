#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pycryptodome

    mkdir -p /home/user/vault
    cd /home/user/vault

    cat << 'EOF' > service.py
import json
import hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

IV = b'0123456789abcdef'

def get_key(pin: str) -> bytes:
    # Key derived from a 4-digit PIN
    return hashlib.md5(pin.zfill(4).encode()).digest()

def encrypt_token(data: dict, pin: str) -> bytes:
    key = get_key(pin)
    cipher = AES.new(key, AES.MODE_CBC, iv=IV)
    padded_data = pad(json.dumps(data).encode(), AES.block_size)
    return cipher.encrypt(padded_data)

def decrypt_token(ciphertext: bytes, pin: str) -> dict:
    key = get_key(pin)
    cipher = AES.new(key, AES.MODE_CBC, iv=IV)
    decrypted = unpad(cipher.decrypt(ciphertext), AES.block_size)
    return json.loads(decrypted.decode())
EOF

    python3 -c "
import service
import binascii
token = service.encrypt_token({'user': 'guest', 'role': 'guest'}, '7391')
with open('low_priv.hex', 'w') as f:
    f.write(binascii.hexlify(token).decode())
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
