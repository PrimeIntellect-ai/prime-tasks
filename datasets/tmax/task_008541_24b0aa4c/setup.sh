#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /home/user/workspace/logs
    mkdir -p /home/user/workspace/auth_service

    cat << 'EOF' > /home/user/workspace/auth_service/app.py
from flask import Flask, request, jsonify, make_response
import logging

app = Flask(__name__)
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

@app.route('/login', methods=['POST'])
def login():
    data = request.json
    if not data:
        return jsonify({"error": "Bad request"}), 400

    if data.get('username') == 'auditor' and data.get('password') == 'compliance_password':
        resp = make_response(jsonify({"status": "success", "audit_receipt": "AUDIT-7734-TX99"}))
        # Vulnerability: Missing Secure flag
        resp.set_cookie('session_token', 'token_val_99283', httponly=True, secure=False)
        return resp
    else:
        return jsonify({"status": "failed"}), 401

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /home/user/workspace/logs/access.log
10.0.0.5 - - [10/Oct/2023:13:55:36 +0000] "POST /login HTTP/1.1" 401 120 "-" "curl/7.68.0"
192.168.1.55 - - [10/Oct/2023:14:02:10 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.55 - - [10/Oct/2023:14:02:25 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.55 - - [10/Oct/2023:14:02:40 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.55 - - [10/Oct/2023:14:02:55 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.100 - - [10/Oct/2023:14:05:00 +0000] "POST /login HTTP/1.1" 401 120 "-" "Mozilla/5.0"
EOF

    cat << 'EOF' > /home/user/workspace/logs/auth.json
{"timestamp": "2023-10-10T13:55:36Z", "ip": "10.0.0.5", "username": "admin", "status": "failed"}
{"timestamp": "2023-10-10T14:02:10Z", "ip": "192.168.1.55", "username": "root", "status": "failed"}
{"timestamp": "2023-10-10T14:02:25Z", "ip": "192.168.1.55", "username": "admin", "status": "failed"}
{"timestamp": "2023-10-10T14:02:40Z", "ip": "192.168.1.55", "username": "user", "status": "failed"}
{"timestamp": "2023-10-10T14:02:55Z", "ip": "192.168.1.55", "username": "test", "status": "failed"}
{"timestamp": "2023-10-10T14:05:00Z", "ip": "192.168.1.100", "username": "auditor", "status": "failed"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
