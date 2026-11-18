#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    # 1. Create legacy_token.bin
    python3 -c '
pt = b"{\"user\":\"admin\",\"action\":\"rotate\"}"
key = b"s3cR"
ct = bytes([pt[i] ^ key[i % 4] for i in range(len(pt))])
with open("/home/user/legacy_token.bin", "wb") as f: f.write(ct)
'

    # 2. Create rotation_scripts
    mkdir -p /home/user/rotation_scripts
    touch /home/user/rotation_scripts/clean_logs.py
    touch /home/user/rotation_scripts/rotate_keys.py
    touch /home/user/rotation_scripts/notify_admin.py

    # 3. Create Certificates
    mkdir -p /home/user/certs
    cd /home/user/certs
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.crt -subj "/CN=Root CA"
    openssl genrsa -out int.key 2048
    openssl req -new -key int.key -out int.csr -subj "/CN=Intermediate CA"

    echo "basicConstraints=CA:TRUE" > extfile.cnf
    openssl x509 -req -in int.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out intermediate.crt -days 500 -sha256 -extfile extfile.cnf

    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/CN=Server"
    openssl x509 -req -in server.csr -CA intermediate.crt -CAkey int.key -CAcreateserial -out server.crt -days 365 -sha256

    chmod -R 777 /home/user

    # Fix specific permissions required by the test
    chmod 755 /home/user/rotation_scripts/clean_logs.py
    chmod 755 /home/user/rotation_scripts/notify_admin.py
