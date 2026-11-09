#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl cargo
    pip3 install pytest cryptography

    mkdir -p /home/user/audit/logs/

    # Generate dummy RSA cert
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/audit/server.key -out /home/user/audit/server.crt -days 365 -nodes -subj "/CN=test.internal" 2>/dev/null

    # Python script to generate the AES key, encrypt actions, and create JWTs
    cat << 'EOF' > /tmp/setup.py
import os
import base64
import json
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

os.system("openssl x509 -in /home/user/audit/server.crt -pubkey -noout | openssl rsa -pubin -outform DER > /tmp/pub.der 2>/dev/null")

with open("/tmp/pub.der", "rb") as f:
    pub_der = f.read()

digest = hashes.Hash(hashes.SHA256(), backend=default_backend())
digest.update(pub_der)
pub_hash = digest.finalize()
aes_key = pub_hash[:16]

def encrypt_action(action_str):
    cipher = Cipher(algorithms.AES(aes_key), modes.ECB(), backend=default_backend())
    encryptor = cipher.encryptor()
    ct = encryptor.update(action_str.encode('utf-8')) + encryptor.finalize()
    return ct.hex()

hex1 = encrypt_action("EXFILTRATE_USERS")
hex2 = encrypt_action("DELETE_ALL_AUDIT")

def base64url_encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

def make_jwt(header, payload):
    h = base64url_encode(json.dumps(header, separators=(',', ':')).encode('utf-8'))
    p = base64url_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8'))
    return f"{h}.{p}."

tok1 = make_jwt({"alg":"HS256"}, {"role":"user","encrypted_action":""}) + "fake_sig"
tok2 = make_jwt({"alg":"none"}, {"role":"admin","encrypted_action":hex1})
tok3 = make_jwt({"alg":"none"}, {"role":"admin","encrypted_action":hex2})

log_content = f"""[2023-10-01T12:00:00Z] GET /api/data Authorization: Bearer {tok1}
[2023-10-01T12:05:00Z] POST /api/admin Authorization: Bearer {tok2}
[2023-10-01T12:10:00Z] POST /api/admin Authorization: Bearer {tok3}
"""
with open("/home/user/audit/logs/access.log", "w") as f:
    f.write(log_content)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
