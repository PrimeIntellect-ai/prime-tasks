#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest flask

    mkdir -p /home/user/webapp
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/webapp/utils.py
def check_auth(user, pwd):
    return user == "admin" and pwd == "secret"
EOF

    cat << 'EOF' > /home/user/webapp/config.py
SECRET_KEY = "super-secret-key-123"
DEBUG = False
EOF

    cat << 'EOF' > /tmp/old_app.py
from flask import Flask, request, redirect

app = Flask(__name__)

@app.route('/login', methods=['POST'])
def login():
    username = request.form.get('username')
    password = request.form.get('password')

    if username == 'admin' and password == 'secret':
        next_url = request.args.get('next', '/dashboard')
        if not next_url.startswith('/') or next_url.startswith('//'):
            next_url = '/dashboard'
        return redirect(next_url)
    return "Unauthorized", 401
EOF

    cd /home/user/webapp
    sha256sum utils.py > /home/user/backup/hashes.txt
    sha256sum config.py >> /home/user/backup/hashes.txt
    sha256sum /tmp/old_app.py | sed 's|/tmp/old_app.py|app.py|' >> /home/user/backup/hashes.txt

    cat << 'EOF' > /home/user/webapp/app.py
from flask import Flask, request, redirect

app = Flask(__name__)

@app.route('/login', methods=['POST'])
def login():
    username = request.form.get('username')
    password = request.form.get('password')

    if username == 'admin' and password == 'secret':
        # Vulnerable implementation (Open Redirect)
        next_url = request.args.get('next', '/dashboard')
        return redirect(next_url)
    return "Unauthorized", 401
EOF

    rm /tmp/old_app.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
