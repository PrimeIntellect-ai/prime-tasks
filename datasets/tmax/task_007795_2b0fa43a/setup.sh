#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp
    mkdir -p /home/user/ssh_configs

    cat << 'EOF' > /home/user/scan_data.json
[
  {"ip": "192.168.1.10", "port": 22, "service": "ssh", "encryption": "strong", "cve_count": 0},
  {"ip": "192.168.1.10", "port": 23, "service": "telnet", "encryption": "none", "cve_count": 1},
  {"ip": "192.168.1.12", "port": 80, "service": "http", "encryption": "none", "cve_count": 0},
  {"ip": "192.168.1.15", "port": 445, "service": "smb", "encryption": "none", "cve_count": 0},
  {"ip": "192.168.1.20", "port": 443, "service": "https", "encryption": "strong", "cve_count": 3}
]
EOF

    cat << 'EOF' > /home/user/webapp/app.py
from flask import Flask, request, make_response

app = Flask(__name__)

@app.route('/greet')
def greet():
    name = request.args.get('name', 'Guest')
    html = f"<html><body><h1>Hello, {name}!</h1></body></html>"
    response = make_response(html)
    return response

if __name__ == '__main__':
    app.run(port=8080)
EOF

    cat << 'EOF' > /home/user/ssh_configs/sshd_config
Port 22
PermitRootLogin yes
MaxAuthTries 6
PasswordAuthentication yes
X11Forwarding no
EOF

    chmod -R 777 /home/user
