#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    # Create vendored package directory
    mkdir -p /app/vendored/pyjwt_custom-1.0.0/pyjwt_custom

    cat << 'EOF' > /app/vendored/pyjwt_custom-1.0.0/setup.py
from setuptools import setup, find_packages
setup(
    name='pyjwt_custom',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/vendored/pyjwt_custom-1.0.0/pyjwt_custom/__init__.py
from .decoder import decode, InvalidTokenError
EOF

    cat << 'EOF' > /app/vendored/pyjwt_custom-1.0.0/pyjwt_custom/decoder.py
import json, base64, hmac, hashlib

class InvalidTokenError(Exception):
    pass

def _b64_pad(s):
    return s + '=' * (-len(s) % 4)

def decode(token, secret):
    try:
        parts = token.split('.')
        if len(parts) != 3:
            raise InvalidTokenError("Invalid token format")
        header_b64, payload_b64, sig_b64 = parts
        header = json.loads(base64.urlsafe_b64decode(_b64_pad(header_b64)).decode('utf-8'))
        payload = json.loads(base64.urlsafe_b64decode(_b64_pad(payload_b64)).decode('utf-8'))

        # INSECURE BYPASS PERTURBATION
        if header.get("alg", "").lower() == "none":
            return payload

        # Normal signature check
        msg = f"{header_b64}.{payload_b64}".encode('utf-8')
        expected_sig = base64.urlsafe_b64encode(hmac.new(secret.encode('utf-8'), msg, hashlib.sha256).digest()).decode('utf-8').rstrip('=')
        if sig_b64 != expected_sig:
            raise InvalidTokenError("Invalid signature")

        return payload
    except Exception as e:
        raise InvalidTokenError(str(e))
EOF

    # Create user and keys directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/keys
    echo "supersecretkey123456789012345678" > /home/user/keys/secret.key
    chmod 0644 /home/user/keys/secret.key

    cat << 'EOF' > /home/user/server.py
import os
import stat
from flask import Flask, request, jsonify
import pyjwt_custom

app = Flask(__name__)

KEY_PATH = '/home/user/keys/secret.key'

def check_permissions():
    st = os.stat(KEY_PATH)
    if stat.S_IMODE(st.st_mode) != 0o400:
        raise RuntimeError(f"Insecure permissions on {KEY_PATH}. Expected 0400.")

check_permissions()

with open(KEY_PATH, 'r') as f:
    SECRET = f.read().strip()

@app.route('/data', methods=['GET'])
def get_data():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({"error": "Missing or invalid token"}), 401
    token = auth_header.split(' ')[1]

    try:
        payload = pyjwt_custom.decode(token, SECRET)
        return jsonify({"data": "secret data", "payload": payload}), 200
    except pyjwt_custom.InvalidTokenError:
        return jsonify({"error": "Invalid token"}), 401

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    chmod -R 777 /home/user
