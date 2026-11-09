#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/api

    cat << 'EOF' > /home/user/api/requirements.txt
Flask==2.2.5
Werkzeug==2.2.3
EOF

    cat << 'EOF' > /home/user/api/app.py
from flask import Flask, request, jsonify
import base64
import json
import hmac
import hashlib

app = Flask(__name__)
SECRET_KEY = b"super_secret_key_12345"

def decode_jwt(token):
    try:
        parts = token.split('.')
        if len(parts) != 3:
            return None

        header_b64, payload_b64, signature_b64 = parts

        # Add padding if necessary
        header_pad = header_b64 + '=' * (-len(header_b64) % 4)
        payload_pad = payload_b64 + '=' * (-len(payload_b64) % 4)

        header = json.loads(base64.urlsafe_b64decode(header_pad))
        payload = json.loads(base64.urlsafe_b64decode(payload_pad))

        alg = header.get('alg', '').lower()

        # VULNERABILITY: Accepts alg=none
        if alg == 'none':
            return payload

        if alg == 'hs256':
            expected_sig = base64.urlsafe_b64encode(
                hmac.new(SECRET_KEY, f"{header_b64}.{payload_b64}".encode(), hashlib.sha256).digest()
            ).decode().rstrip('=')

            if hmac.compare_digest(expected_sig, signature_b64):
                return payload

        return None
    except Exception as e:
        return None

@app.route('/admin/data', methods=['GET'])
def admin_data():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({"error": "Missing token"}), 401

    token = auth_header.split(' ')[1]
    payload = decode_jwt(token)

    if payload and payload.get('role') == 'admin':
        return jsonify({"data": "FLAG_SECURE_JWT_DATA_9921"}), 200

    return jsonify({"error": "Unauthorized"}), 403

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/api/server.log
192.168.1.50 - - [10/Oct/2023:13:55:36 +0000] "GET /admin/data HTTP/1.1" 401 - "-" "curl/7.68.0"
192.168.1.10 - - [10/Oct/2023:13:56:10 +0000] "GET /admin/data HTTP/1.1" 403 - "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGVzdCIsInJvbGUiOiJ1c2VyIn0.signature" "Mozilla/5.0"
10.0.0.5 - - [10/Oct/2023:14:01:22 +0000] "GET /admin/data HTTP/1.1" 200 - "Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoiYWRtaW4ifQ." "python-requests/2.25.1"
192.168.1.12 - - [10/Oct/2023:14:05:00 +0000] "GET /admin/data HTTP/1.1" 403 - "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoibnBvIiwicm9sZSI6InVzZXIifQ.signature" "Mozilla/5.0"
172.16.0.4 - - [10/Oct/2023:14:10:11 +0000] "GET /admin/data HTTP/1.1" 200 - "Bearer eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoiYWRtaW4ifQ." "curl/7.68.0"
10.0.0.5 - - [10/Oct/2023:14:15:33 +0000] "GET /admin/data HTTP/1.1" 200 - "Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4ifQ." "python-requests/2.25.1"
EOF

    cat << 'EOF' > /home/user/start_server.sh
#!/bin/bash
cd /home/user/api
nohup python3 app.py > /dev/null 2>&1 &
sleep 2
EOF
    chmod +x /home/user/start_server.sh

    chmod -R 777 /home/user
