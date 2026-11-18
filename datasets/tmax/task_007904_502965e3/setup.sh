#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/server.py
from flask import Flask, request, jsonify
import base64
import json

app = Flask(__name__)

def decode_base64_url(data):
    padding = '=' * (4 - (len(data) % 4))
    return base64.burlsafe_b64decode(data + padding).decode('utf-8')

@app.route('/admin', methods=['GET'])
def admin():
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return jsonify({"error": "Missing token"}), 401

    token = auth_header.split(' ')[1]
    parts = token.split('.')

    if len(parts) < 2:
        return jsonify({"error": "Invalid token"}), 401

    try:
        header = json.loads(decode_base64_url(parts[0]))
        payload = json.loads(decode_base64_url(parts[1]))

        # VULNERABILITY: Accepts alg: none without signature verification
        if header.get('alg', '').lower() == 'none':
            if payload.get('role') == 'admin':
                return jsonify({"status": "success", "secret_data": "FLAG{jwt_bypass_successful_9921}"}), 200
            else:
                return jsonify({"error": "Forbidden"}), 403
        else:
            return jsonify({"error": "Signature verification failed"}), 401
    except Exception as e:
        return jsonify({"error": "Malformed token"}), 400

@app.route('/search', methods=['POST'])
def search():
    data = request.get_json(silent=True) or {}
    query = data.get('query', '')

    # VULNERABILITY: Fake SQLi endpoint
    if "' OR 1=1 --" in query:
        return jsonify({"error": "Database syntax error near '--'"}), 500

    # VULNERABILITY: Fake XSS endpoint (Reflected XSS)
    return f"<html><body>Results for {query}</body></html>", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    chmod -R 777 /home/user
