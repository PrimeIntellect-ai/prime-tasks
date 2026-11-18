#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    mkdir -p /home/user/forensics
    mkdir -p /home/user/.ssh
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/forensics/encoded_payloads.log
aHR0cHM6Ly9hdHRhY2tlci5uZXQvbG9naW4=
aHR0cDovL21hbGljaW91cy1waGlzaC5jb20vY2FwdHVyZT91c2VyPWFkbWlu
aHR0cHM6Ly9hdHRhY2tlci5uZXQvcmVkaXJlY3Q=
aHR0cHM6Ly9iYWRndXkuaW8vZHJvcHBlci5zaA==
EOF

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... fakekey1 backdoor@hacker.io
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD... validkey2 analyst@soc.local
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... fakekey3 root@pwned.box
EOF

    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, make_response

app = Flask(__name__)

@app.route('/login')
def login():
    response = make_response("Login Page")
    response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'"
    return response

if __name__ == '__main__':
    app.run()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
