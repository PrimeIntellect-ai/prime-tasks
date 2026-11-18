#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation/certs
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/investigation/access.log
10.0.0.15 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024
10.0.0.15 - - [10/Oct/2023:13:56:01 +0000] "POST /upload?path=images/logo.png HTTP/1.1" 200 512
192.168.45.99 - - [10/Oct/2023:14:12:05 +0000] "POST /upload?path=../../../../home/user/.ssh/authorized_keys HTTP/1.1" 200 128
10.0.0.18 - - [10/Oct/2023:14:15:22 +0000] "GET /api/status HTTP/1.1" 200 64
EOF

    cat << 'EOF' > /home/user/investigation/auth_service.py
import base64

def generate_token(username):
    # Highly secure proprietary encryption
    key = "S3cr3tK3y"
    encoded = base64.b64encode(username.encode()).decode()
    token = ""
    for i in range(len(encoded)):
        token += chr(ord(encoded[i]) ^ ord(key[i % len(key)]))
    return base64.b64encode(token.encode()).decode()

def verify_token(username, token):
    return generate_token(username) == token
EOF

    openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 -keyout /tmp/rootCA.key -out /home/user/investigation/certs/rootCA.pem -subj "/C=US/ST=State/L=City/O=Org/CN=RootCA"
    openssl req -new -newkey rsa:2048 -nodes -keyout /tmp/valid.key -out /tmp/valid.csr -subj "/C=US/ST=State/L=City/O=Org/CN=ValidApp"
    openssl x509 -req -in /tmp/valid.csr -CA /home/user/investigation/certs/rootCA.pem -CAkey /tmp/rootCA.key -CAcreateserial -out /home/user/investigation/certs/service_alpha.pem -days 365 -sha256
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/rogue.key -out /home/user/investigation/certs/service_beta.pem -subj "/C=US/ST=State/L=City/O=Org/CN=ValidApp"

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... legitimate_user_key
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... attacker_key_from_192.168.45.99
EOF

    chmod -R 777 /home/user
