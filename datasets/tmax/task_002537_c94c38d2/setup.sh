#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libssl-dev \
        build-essential

    pip3 install pytest cryptography

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the video file with the key
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=2 -vf "drawtext=text='openssl enc -aes-256-cbc -k \"X7k9Pq2mN4vB1cL5\"':fontcolor=white:fontsize=24:x=10:y=10" -c:v libx264 /app/session.mp4

    # Generate corpus files using Python
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import hashlib
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend

# 16-byte key padded to 32 bytes for AES-256
key = b'X7k9Pq2mN4vB1cL5'.ljust(32, b'\0')
iv = b'\0' * 16

def encrypt(data):
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(data) + padder.finalize()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    return encryptor.update(padded_data) + encryptor.finalize()

def write_file(path, filename, payload_bytes, tamper_hash=False):
    h = hashlib.sha256(payload_bytes).hexdigest()
    if tamper_hash:
        h = hashlib.sha256(b"tampered_hash_value").hexdigest()
    b64 = base64.b64encode(payload_bytes).decode('utf-8')
    with open(path, "w") as f:
        f.write(f"FILENAME: {filename}\nSHA256: {h}\nPAYLOAD: {b64}\n")

# Clean corpus
for i in range(10):
    write_file(f"/app/corpus/clean/clean_{i}.txt", f"file_{i}.txt", f"clean data {i}".encode())

# Evil corpus - Path traversal
for i in range(3):
    write_file(f"/app/corpus/evil/evil_pt_{i}.txt", f"../file_{i}.txt", b"random data")

# Evil corpus - Tampered hash
for i in range(3):
    write_file(f"/app/corpus/evil/evil_tamp_{i}.txt", f"file_{i}.txt", b"random data", tamper_hash=True)

# Evil corpus - Encrypted malicious payload
for i in range(4):
    enc = encrypt(b"some prefix REDTEAM_STRIKE some suffix")
    write_file(f"/app/corpus/evil/evil_enc_{i}.txt", f"file_{i}.txt", enc)
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
