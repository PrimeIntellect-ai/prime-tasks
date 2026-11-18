#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl procps
    pip3 install pytest flask

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the secret key
    echo "SUPER_SECRET_TOKEN_99812" > /home/user/secret_key.txt

    # Create the vulnerable Flask app
    cat << 'EOF' > /home/user/app.py
import os
from flask import Flask, request

app = Flask(__name__)

def is_valid_sha256(s):
    return len(s) == 64 and all(c in '0123456789abcdef' for c in s.lower())

@app.route('/log', methods=['POST'])
def log_activity():
    token = request.cookies.get('Session-Token')
    if not token or not is_valid_sha256(token):
        return "Unauthorized\n", 401

    client_ip = request.headers.get('X-Forwarded-For', '')
    if client_ip:
        os.system(f"echo {client_ip} >> /tmp/access.log")
        return "Logged\n", 200
    return "No IP\n", 400

if __name__ == '__main__':
    app.run(port=8080)
EOF

    # Setup automatic startup of the app when a shell is launched
    cat << 'EOF' > /etc/profile.d/start_app.sh
if ! pgrep -f "python3 /home/user/app.py" > /dev/null; then
    python3 /home/user/app.py > /dev/null 2>&1 &
    sleep 2
fi
EOF
    chmod +x /etc/profile.d/start_app.sh

    # Set permissions
    chmod -R 777 /home/user
