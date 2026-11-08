#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the TLS certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/dummy.key -out /home/user/server.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=ComplianceCA" 2>/dev/null

    # Create a Python script to generate the encrypted logs
    cat << 'EOF' > /tmp/setup_logs.py
import json
from cryptography.fernet import Fernet

key = Fernet.generate_key()
with open('/home/user/secret.key', 'wb') as f:
    f.write(key)

logs = [
    {"id": "A01", "timestamp": "2023-10-01T10:00:00Z", "message": "User admin logged in from 192.168.1.50."},
    {"id": "A02", "timestamp": "2023-10-01T10:05:12Z", "message": "Payment processed for card 1234-5678-9012-3456 successfully."},
    {"id": "A03", "timestamp": "2023-10-01T10:15:30Z", "message": "Failed API request from external IP."},
    {"id": "A04", "timestamp": "2023-10-01T10:20:00Z", "message": "Direct billing account updated for 9876543210987654."}
]

f = Fernet(key)
encrypted_data = f.encrypt(json.dumps(logs).encode('utf-8'))

with open('/home/user/audit_logs.enc', 'wb') as f:
    f.write(encrypted_data)
EOF

    python3 /tmp/setup_logs.py

    chmod -R 777 /home/user
