#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/evidence

    cat << 'EOF' > /tmp/setup.py
import os
import base64
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import ciphers, hashes
from cryptography.hazmat.primitives.ciphers import algorithms, modes
from cryptography.hazmat.primitives import serialization

evidence_dir = "/home/user/evidence"
os.makedirs(evidence_dir, exist_ok=True)

# 1. Generate RSA Key
private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.TraditionalOpenSSL,
    encryption_algorithm=serialization.NoEncryption()
)
with open(os.path.join(evidence_dir, "attacker.key"), "wb") as f:
    f.write(pem)

# 2. Generate AES Key & Encrypt it with RSA
aes_key = os.urandom(32)
encrypted_aes_key = private_key.public_key().encrypt(
    aes_key,
    padding.PKCS1v15()
)
b64_session_token = base64.b64encode(encrypted_aes_key).decode('utf-8')

# 3. Create access.log
log_content = f"""192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326 "-" "Mozilla/5.0"
10.0.0.5 - - [10/Oct/2023:13:57:12 -0700] "POST /api/exfiltrate HTTP/1.1" 201 42 "-" "Mozilla/5.0" "Session-Token={b64_session_token}"
192.168.1.11 - - [10/Oct/2023:13:58:00 -0700] "GET /api/status HTTP/1.1" 404 123 "-" "curl/7.68.0"
"""
with open(os.path.join(evidence_dir, "access.log"), "w") as f:
    f.write(log_content)

# 4. Create plaintext, encrypt with AES
plaintext = b"""EXFILTRATION LOG:
Target Admin: superadmin@corp.local accessed via 203.0.113.45
Target User: jdoe123@gmail.com accessed via 198.51.100.2
Database dumped successfully.
"""
iv = os.urandom(16)
cipher = ciphers.Cipher(algorithms.AES(aes_key), modes.CBC(iv))
encryptor = cipher.encryptor()

# PKCS7 padding for AES
pad_len = 16 - (len(plaintext) % 16)
padded_plaintext = plaintext + bytes([pad_len] * pad_len)
ciphertext = encryptor.update(padded_plaintext) + encryptor.finalize()

with open(os.path.join(evidence_dir, "staging.enc"), "wb") as f:
    f.write(iv + ciphertext)

# Expected Redacted Output (for validation framework)
expected_output = """EXFILTRATION LOG:
Target Admin: [REDACTED_EMAIL] accessed via [REDACTED_IP]
Target User: [REDACTED_EMAIL] accessed via [REDACTED_IP]
Database dumped successfully.
"""
with open(os.path.join(evidence_dir, ".expected_clean.txt"), "w") as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
