#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/vulnerable_app.py
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/')
def index():
    return "Welcome to the Network Diagnostic Tool"

@app.route('/ping')
def ping():
    host = request.args.get('host', '127.0.0.1')
    # Vulnerable to OS Command Injection (CWE-78)
    result = os.popen(f"ping -c 1 {host}").read()
    return f"<pre>{result}</pre>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [24/Oct/2023:10:15:32 +0000] "GET / HTTP/1.1" 200 45 "-" "Mozilla/5.0"
192.168.1.15 - - [24/Oct/2023:10:16:01 +0000] "GET /ping?host=8.8.8.8 HTTP/1.1" 200 302 "-" "curl/7.68.0"
10.0.0.5 - - [24/Oct/2023:11:05:12 +0000] "GET /ping?host=1.1.1.1 HTTP/1.1" 200 310 "-" "Mozilla/5.0"
172.16.22.109 - - [24/Oct/2023:13:44:55 +0000] "GET /ping?host=127.0.0.1;cat%20/etc/passwd HTTP/1.1" 200 1024 "-" "python-requests/2.25.1"
192.168.1.20 - - [24/Oct/2023:14:10:22 +0000] "GET / HTTP/1.1" 200 45 "-" "Mozilla/5.0"
EOF

    touch /home/user/evidence/config.yaml
    touch /home/user/evidence/readme.txt
    touch /home/user/evidence/system_info.sh
    touch /home/user/evidence/.hidden_cfg
    touch /home/user/evidence/persistence_bind.sh

    chmod -R 777 /home/user

    # Restore specific permissions required by the test
    chmod 644 /home/user/evidence/config.yaml
    chmod 644 /home/user/evidence/readme.txt
    chmod 755 /home/user/evidence/system_info.sh
    chmod 644 /home/user/evidence/.hidden_cfg
    chmod 777 /home/user/evidence/persistence_bind.sh
