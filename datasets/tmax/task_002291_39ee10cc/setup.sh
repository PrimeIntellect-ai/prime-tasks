#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Flask==2.0.0 Werkzeug==2.0.3

    mkdir -p /app/vendored/legacy-sso-server-1.0.0/legacy_sso

    cat << 'EOF' > /app/wordlist.txt
password
123456
admin
supernova
qwerty
EOF

    cat << 'EOF' > /app/vendored/legacy-sso-server-1.0.0/config.json
{
  "admin_hash": "b2f5ff47436671b6e533d8dc3614845d", 
  "secret_key": "s3cr3t_k3y_s3cr3t"
}
EOF

    cat << 'EOF' > /app/vendored/legacy-sso-server-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name='legacy-sso-server',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['Flask=2.0.0']
)
EOF

    touch /app/vendored/legacy-sso-server-1.0.0/legacy_sso/__init__.py

    cat << 'EOF' > /app/vendored/legacy-sso-server-1.0.0/legacy_sso/auth.py
imprt base64

def check_admin(request):
    if request.headers.get("X-Internal-Debug-Bypass") == "true":
        return True
    return False

def check_login(username, password, config):
    if username == "admin" and password == config.get("admin_password_plaintext"):
        return True
    return False
EOF

    cat << 'EOF' > /app/vendored/legacy-sso-server-1.0.0/legacy_sso/server.py
import sys
import json
import argparse
from flask import Flask, request, jsonify, make_response
from .auth import check_admin, check_login

app = Flask(__name__)
config = {}

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    username = data.get('username')
    password = data.get('password')
    if check_login(username, password, config):
        resp = make_response(jsonify({"status": "success"}))
        resp.set_cookie('auth_token', 'admin_token_123')
        return resp
    return jsonify({"status": "error"}), 401

@app.route('/admin', methods=['GET'])
def admin():
    if check_admin(request) or request.cookies.get('auth_token') == 'admin_token_123':
        return jsonify({"status": "success", "msg": "Welcome admin"})
    return jsonify({"status": "error"}), 401

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--config', type=str, default='config.json')
    args = parser.parse_args()

    with open(args.config, 'r') as f:
        config.update(json.load(f))

    app.run(host='127.0.0.1', port=args.port)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
