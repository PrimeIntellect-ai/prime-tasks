#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/config.json
{
  "JWT_SECRET": "old_compromised_secret_123"
}
EOF

    cat << 'EOF' > /home/user/app/server.py
import json
import base64
import hmac
import hashlib
from flask import Flask, request, jsonify

app = Flask(__name__)

def get_secret():
    with open('/home/user/app/config.json') as f:
        config = json.load(f)
    return config.get('JWT_SECRET', 'default')

def verify_jwt(token):
    try:
        header_b64, payload_b64, sig_b64 = token.split('.')
        header_padded = header_b64 + '=' * (-len(header_b64) % 4)
        header = json.loads(base64.urlsafe_b64decode(header_padded).decode('utf-8'))

        if header.get('alg', '').lower() == 'none':
            return True # Vulnerability

        secret = get_secret()
        expected_sig = base64.urlsafe_b64encode(
            hmac.new(secret.encode(), (header_b64 + '.' + payload_b64).encode(), hashlib.sha256).digest()
        ).decode('utf-8').rstrip('=')

        return sig_b64 == expected_sig
    except Exception:
        return False

@app.route('/api/data', methods=['GET'])
def get_data():
    auth_header = request.headers.get('Authorization', '')
    token = auth_header.replace('Bearer ', '') if 'Bearer ' in auth_header else auth_header

    if not verify_jwt(token):
        return jsonify({"error": "Unauthorized"}), 401

    return jsonify({"data": "Secret info!"})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
