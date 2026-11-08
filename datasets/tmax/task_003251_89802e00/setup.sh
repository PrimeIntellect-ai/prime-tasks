#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssl
    pip3 install pytest flask

    mkdir -p /app
    # Create the Flask backend receiver
    cat << 'EOF' > /app/receiver.py
from flask import Flask, request
app = Flask(__name__)
@app.route('/log', methods=['POST'])
def log():
    return "Log received", 200
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create the Oracle
    cat << 'EOF' > /app/oracle_normalizer.py
import sys
import hmac
import hashlib

def verify():
    key = b'COMPLIANCE_KEY_2024'
    for line in sys.stdin:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split(':', 1)
        if len(parts) != 2:
            print(f"[TAMPERED] {line}")
            continue
        mac_hex, msg = parts
        expected_mac = hmac.new(key, msg.encode('utf-8'), hashlib.sha256).hexdigest()
        if hmac.compare_digest(expected_mac, mac_hex):
            print(f"[VERIFIED] {msg}")
        else:
            print(f"[TAMPERED] {msg}")

if __name__ == '__main__':
    verify()
EOF
    chmod +x /app/oracle_normalizer.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/certs
    chown -R user:user /home/user/certs
    chmod -R 777 /home/user
