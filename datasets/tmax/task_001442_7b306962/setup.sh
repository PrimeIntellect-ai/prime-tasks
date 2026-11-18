#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
from flask import Flask, request, jsonify, make_response

app = Flask(__name__)

@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    if data and data.get('username') == 'admin' and data.get('password') == 'password123':
        resp = make_response(jsonify({"message": "Logged in"}))
        # Vulnerable configuration: Missing 'Secure' flag, missing some headers
        resp.set_cookie('session_id', 'abc123xyz', httponly=True)
        resp.headers['X-Content-Type-Options'] = 'nosniff'
        resp.headers['X-Frame-Options'] = 'DENY'
        # Missing Strict-Transport-Security and Content-Security-Policy
        return resp
    return jsonify({"error": "Unauthorized"}), 401

@app.route('/api/users', methods=['GET'])
def get_users():
    cookie = request.cookies.get('session_id')
    if cookie != 'abc123xyz':
        return jsonify({"error": "Unauthorized"}), 401

    users = [
        {"name": "Alice Smith", "ssn": "123-45-6789", "role": "Manager"},
        {"name": "Bob Jones", "ssn": "987-65-4321", "role": "Developer"}
    ]
    return jsonify(users)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    chmod -R 777 /home/user
