#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl coreutils gawk
pip3 install pytest flask

mkdir -p /home/user

cat << 'EOF' > /home/user/app.py
import base64
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str).decode('utf-8')

@app.route('/api/reports', methods=['GET'])
def get_reports():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({"error": "Missing token"}), 401

    token = auth_header.split(' ')[1]
    parts = token.split('.')
    if len(parts) != 3:
        return jsonify({"error": "Invalid token format"}), 401

    try:
        header = json.loads(base64url_decode(parts[0]))
        payload = json.loads(base64url_decode(parts[1]))

        # Vulnerable implementation: trusts alg=none
        if header.get('alg', '').lower() == 'none':
            pass # Signature verification skipped!
        else:
            return jsonify({"error": "Invalid signature"}), 403

        if payload.get('role') != 'admin':
            return jsonify({"error": "Unauthorized"}), 403

        return jsonify({
            "reports": [
                {"id": 1, "data": "Routine server maintenance completed.", "author": "alice"},
                {"id": 2, "data": "User 123-45-6789 reported a billing error.", "author": "bob"},
                {"id": 3, "data": "Contractor 987-65-4321 requires access to db-prod.", "author": "charlie"}
            ]
        })
    except Exception as e:
        return jsonify({"error": "Token parsing failed"}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

sha256sum /home/user/app.py | awk '{print $1}' > /home/user/manifest.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
