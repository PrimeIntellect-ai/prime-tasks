#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest cryptography flask pyopenssl

    mkdir -p /home/user/app_backup/certs

    cat << 'EOF' > /home/user/wordlist.txt
password
admin
123456
supersecret
dragon
purplemonkey
adm1n!
EOF

    cat << 'EOF' > /home/user/app_backup/admin_hash.txt
b9c5f87b3260dd2ec5db9ad80ca7b4fc7da1b1bf0529d2011b913d33924f0f67
EOF

    cat << 'EOF' > /home/user/app_backup/server.py
import os
from flask import Flask, request

app = Flask(__name__)

@app.route('/ping')
def handle_ping():
    target = request.args.get('ip', '')
    # VULNERABILITY: OS Command Injection (CWE-78)
    result = os.popen(f"ping -c 1 {target}").read()
    return result

if __name__ == '__main__':
    app.run()
EOF

    cat << 'EOF' > /home/user/app_backup/app.log
[INFO] Application started
[DEBUG] User login attempt: admin
[WARN] Failed transaction for card 1234-5678-9012-3456 due to insufficient funds
[INFO] Cache cleared
[WARN] Failed transaction for card 9876-5432-1098-7654 due to invalid CVV
[INFO] User logout
[DEBUG] Processing batch for cards 1111-2222-3333-4444 and 5555-6666-7777-8888
[INFO] System shutting down
EOF

    cd /home/user/app_backup/certs

    # Generate Root CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root.key -out root.pem -subj "/CN=Root CA"

    # Generate Intermediate CA signed by Root CA
    openssl req -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/CN=Intermediate CA"
    openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root.key -CAcreateserial -out intermediate.pem -days 365

    # Generate Dummy Root CA (to create an invalid chain for leaf)
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout dummy.key -out dummy.pem -subj "/CN=Dummy CA"

    # Generate Leaf signed by Dummy Root CA (so it fails verification against the provided root/intermediate)
    openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=Leaf"
    openssl x509 -req -in leaf.csr -CA dummy.pem -CAkey dummy.key -CAcreateserial -out leaf.pem -days 365

    # Cleanup extra keys and certs not needed for the task
    rm root.key intermediate.key intermediate.csr dummy.key dummy.pem dummy.srl root.srl leaf.key leaf.csr || true

    cd /

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
