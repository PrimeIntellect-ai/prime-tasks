#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl faketime
pip3 install pytest cryptography flask

mkdir -p /home/user/audit_target

cat << 'EOF' > /home/user/audit_target/login.py
from flask import Flask, request, redirect

app = Flask(__name__)

@app.route('/login', methods=['POST'])
def login():
    username = request.form.get('username')
    password = request.form.get('password')

    # Fake authentication logic
    if username == 'admin' and password == 'secret':
        # VULNERABILITY: Open Redirect
        target = request.args.get('return_to_path')
        if target:
            return redirect(target)
        return "Logged in!"
    return "Failed", 401
EOF

chmod 777 /home/user/audit_target/login.py

cat << 'EOF' > /home/user/audit_target/checksum.sha256
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  login.py
EOF

# Generate an expired certificate using faketime
faketime '2020-01-01 00:00:00' openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/audit_target/server.crt -days 10 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=localhost"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
