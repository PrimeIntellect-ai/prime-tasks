#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest flask cryptography

    mkdir -p /home/user/evidence/certs
    cd /home/user/evidence/certs

    # Legitimate CA
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Company/CN=LegitInternalCA"
    # Rogue CA
    openssl req -x509 -newkey rsa:2048 -keyout rogue.key -out rogue.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Hacker/CN=EvilCorpRoot"
    # Server CSR
    openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/C=US/ST=State/L=City/O=Company/CN=internal.service.local"
    # Sign server cert with Rogue CA
    openssl x509 -req -in server.csr -CA rogue.crt -CAkey rogue.key -CAcreateserial -out server.crt -days 365

    cat << 'EOF' > /home/user/evidence/server.py
from flask import Flask, request, redirect

app = Flask(__name__)

@app.route('/login', methods=['POST'])
def login():
    # Authentication logic goes here
    next_url = request.args.get('next')
    if next_url:
        return redirect(next_url)
    return redirect('/home')

if __name__ == '__main__':
    app.run()
EOF

    cat << 'EOF' > /home/user/evidence/payload.py
import os

def steal_data():
    target = "/home/user/secret_master_key.pem"
    try:
        with open(target, "r") as f:
            data = f.read()
            # exfiltrate data...
    except Exception:
        pass

if __name__ == "__main__":
    steal_data()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
