#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    mkdir -p /app/crypt_auth_lib-2.1/crypt_auth_lib
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create setup.py
    cat << 'EOF' > /app/crypt_auth_lib-2.1/setup.py
from setuptools import setup, find_packages

setup(
    name="crypt_auth_lib",
    version="2.1",
    packages=find_packages(),
    install_requires=["cryptography"],
)
EOF

    # Create __init__.py
    cat << 'EOF' > /app/crypt_auth_lib-2.1/crypt_auth_lib/__init__.py
from .decryptor import decrypt_session
EOF

    # Create decryptor.py with the bug (data[:15] instead of data[:16])
    cat << 'EOF' > /app/crypt_auth_lib-2.1/crypt_auth_lib/decryptor.py
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding

def decrypt_session(token_b64, key_str):
    key = key_str.encode('utf-8')
    if len(key) != 16:
        key = key[:16].ljust(16, b'\0')

    data = base64.b64decode(token_b64)
    # BUG: Incorrect IV size extracted
    iv = data[:15]
    ciphertext = data[15:]

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    padded_data = decryptor.update(ciphertext) + decryptor.finalize()

    unpadder = padding.PKCS7(128).unpadder()
    unpadded_data = unpadder.update(padded_data) + unpadder.finalize()

    return unpadded_data
EOF

    # Generate corpora
    python3 -c '
import os
import json
import base64
import random
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding

KEY = b"SuperSecretKey12" # 16 bytes

def encrypt_data(data_bytes):
    iv = os.urandom(16)
    cipher = Cipher(algorithms.AES(KEY), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(data_bytes) + padder.finalize()
    ciphertext = encryptor.update(padded_data) + encryptor.finalize()
    return base64.b64encode(iv + ciphertext).decode("utf-8")

# Generate clean corpus
for i in range(20):
    token = encrypt_data(json.dumps({"user": f"user{i}", "role": "user"}).encode())
    with open(f"/app/corpus/clean/req_{i}.req", "w") as f:
        f.write(f"Host: example.com\nUser-Agent: Mozilla/5.0\nCookie: Session-Token={token}\nAccept: */*\n")

# Generate evil corpus
payloads = ["<script>alert(1)</script>", "javascript:alert(1)", "<img src=x onload=alert(1)>", "admin\" or 1=1--", "union select 1,2,3", "../../../etc/passwd"]
for i in range(20):
    payload = random.choice(payloads)
    if random.choice([True, False]):
        # Payload in header
        token = encrypt_data(json.dumps({"user": f"user{i}", "role": "user"}).encode())
        with open(f"/app/corpus/evil/req_{i}.req", "w") as f:
            f.write(f"Host: example.com\nUser-Agent: {payload}\nCookie: Session-Token={token}\nAccept: */*\n")
    else:
        # Payload in cookie
        token = encrypt_data(json.dumps({"user": f"user{i}", "role": payload}).encode())
        with open(f"/app/corpus/evil/req_{i}.req", "w") as f:
            f.write(f"Host: example.com\nUser-Agent: Mozilla/5.0\nCookie: Session-Token={token}\nAccept: */*\n")
'

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
