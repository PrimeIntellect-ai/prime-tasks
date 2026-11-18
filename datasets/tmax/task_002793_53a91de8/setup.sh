#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev espeak openssl
    pip3 install pytest cryptography

    mkdir -p /app

    # Generate audio file
    espeak -w /app/voicemail.wav "The rotation passphrase is secure rotate alpha seven seven"

    # Generate Root CA
    openssl req -x509 -newkey rsa:2048 -keyout /app/root_ca.key -out /app/root_ca.pem -days 365 -nodes -subj "/CN=RootCA"

    # Create dummy plaintext for sample and hidden payloads
    echo "192.168.10.0/24" > /app/sample.txt
    cat /app/root_ca.pem >> /app/sample.txt

    echo "10.99.0.0/16" > /app/hidden.txt
    cat /app/root_ca.pem >> /app/hidden.txt

    # Encrypt payloads
    python3 -c '
import os, hashlib, base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend

key = hashlib.sha256(b"secure rotate alpha seven seven").digest()

def encrypt_file(in_path, out_path):
    iv = os.urandom(16)
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    padder = padding.PKCS7(128).padder()
    with open(in_path, "rb") as f:
        data = f.read()
    padded_data = padder.update(data) + padder.finalize()
    ct = encryptor.update(padded_data) + encryptor.finalize()
    with open(out_path, "wb") as f:
        f.write(base64.b64encode(iv + ct))

encrypt_file("/app/sample.txt", "/app/sample_payload.enc")
encrypt_file("/app/hidden.txt", "/app/hidden_test_payload.enc")
'

    # Clean up temporary plaintext files
    rm /app/sample.txt /app/hidden.txt /app/root_ca.key

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
