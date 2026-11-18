#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_target
    cd /home/user/audit_target

    # 1. Binary
    cp /bin/ls /home/user/audit_target/app_bin

    # 2. Certificates (Create a valid chain)
    # Generate Root CA
    openssl req -x509 -nodes -newkey rsa:2048 -keyout root.key -out root.pem -days 365 -subj "/CN=Root CA"
    # Generate Intermediate CA
    openssl req -nodes -newkey rsa:2048 -keyout intermediate.key -out intermediate.csr -subj "/CN=Intermediate CA"
    openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root.key -CAcreateserial -out intermediate.pem -days 365
    # Generate Leaf
    openssl req -nodes -newkey rsa:2048 -keyout leaf.key -out leaf.csr -subj "/CN=App Leaf"
    openssl x509 -req -in leaf.csr -CA intermediate.pem -CAkey intermediate.key -CAcreateserial -out leaf.pem -days 365

    # 3. Headers
    cat << 'EOF' > /home/user/audit_target/headers.txt
HTTP/1.1 200 OK
Date: Mon, 01 Jan 2024 12:00:00 GMT
Server: Apache/2.4.41 (Ubuntu)
Content-Security-Policy: default-src 'none'; script-src 'self';
X-Frame-Options: DENY
EOF

    chmod -R 777 /home/user
