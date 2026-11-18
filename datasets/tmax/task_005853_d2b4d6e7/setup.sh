#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib
from cryptography.fernet import Fernet
import configparser

# Ensure directory exists
os.makedirs('/home/user/evidence', exist_ok=True)

# Generate a Fernet key
key = Fernet.generate_key()
cipher = Fernet(key)

# Create config.ini
config = configparser.ConfigParser()
config['security'] = {'log_encryption_key': key.decode('utf-8')}
with open('/home/user/evidence/config.ini', 'w') as f:
    config.write(f)

# Create fake access logs
log_data = """192.168.1.10 - - [10/Oct/2023:13:55:36 -0000] "GET / HTTP/1.1" 200 512
10.0.0.5 - - [10/Oct/2023:13:56:00 -0000] "GET /login?redirect=/dashboard HTTP/1.1" 302 123
172.16.0.44 - - [10/Oct/2023:14:01:22 -0000] "GET /login?redirect=http://evil-phishing.com/login HTTP/1.1" 302 123
192.168.1.11 - - [10/Oct/2023:14:05:00 -0000] "POST /login HTTP/1.1" 200 456
203.0.113.88 - - [10/Oct/2023:14:10:15 -0000] "GET /login?redirect=https://steal-credentials.org/ HTTP/1.1" 302 123
10.0.0.5 - - [10/Oct/2023:14:15:00 -0000] "GET /login?redirect=http://malicious.com HTTP/1.1" 404 123
127.0.0.1 - - [10/Oct/2023:14:20:00 -0000] "GET /login?redirect=/settings HTTP/1.1" 302 123
"""

# Calculate SHA256 checksum
sha256_hash = hashlib.sha256(log_data.encode('utf-8')).hexdigest()
with open('/home/user/evidence/checksum.txt', 'w') as f:
    f.write(sha256_hash)

# Encrypt log data
encrypted_data = cipher.encrypt(log_data.encode('utf-8'))
with open('/home/user/evidence/access.log.enc', 'wb') as f:
    f.write(encrypted_data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
