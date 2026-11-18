#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import base64
import hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend

os.makedirs('/home/user/system', exist_ok=True)
key = b'SixteenByteKey!!'
with open('/home/user/secret.key', 'wb') as f:
    f.write(key)

with open('/home/user/system/auth.conf', 'w') as f: f.write('valid_config_data')
with open('/home/user/system/logger.sh', 'w') as f: f.write('echo "logging"')
with open('/home/user/system/backup_bin', 'w') as f: f.write('binary_data')

h_auth = hashlib.sha256(b'valid_config_data').hexdigest()
h_logger = hashlib.sha256(b'echo "original"').hexdigest()
h_backup = hashlib.sha256(b'binary_data').hexdigest()

with open('/home/user/system_hashes.txt', 'w') as f:
    f.write(f"{h_auth}  auth.conf\n")
    f.write(f"{h_logger}  logger.sh\n")
    f.write(f"{h_backup}  backup_bin\n")

def encrypt_payload(text):
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(text.encode()) + padder.finalize()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    ct = encryptor.update(padded_data) + encryptor.finalize()
    return base64.b64encode(iv + ct).decode()

logs = [
    {"request_id": "req_001", "method": "GET", "url": "/index.html", "status": 200, "payload": ""},
    {"request_id": "req_002", "method": "POST", "url": "/upload?dir=../../system/", "status": 201, "payload": encrypt_payload("Overwrite logger")},
    {"request_id": "req_003", "method": "POST", "url": "/upload?dir=..%2F..%2Fsystem/", "status": 201, "payload": encrypt_payload("Set SUID on backup")},
    {"request_id": "req_004", "method": "POST", "url": "/upload?dir=../../system/", "status": 403, "payload": ""}
]

with open('/home/user/traffic_logs.json', 'w') as f:
    json.dump(logs, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
    # Set SUID bit after chmod -R 777 to prevent it from being overwritten
    chmod 4755 /home/user/system/backup_bin
