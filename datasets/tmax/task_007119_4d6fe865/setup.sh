#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deploy_artifact
    cd /home/user/deploy_artifact

    # 1. Create Python file with vulnerability
    cat << 'EOF' > app.py
import os
from flask import Flask, request
app = Flask(__name__)

@app.route('/ping')
def ping():
    ip = request.args.get('ip', '127.0.0.1')
    return os.popen(f"ping -c 1 {ip}").read()
EOF

    # 2. Create config file and make it world-writable
    echo "debug: true" > config.yaml
    echo "port: 8080" >> config.yaml
    chmod 777 config.yaml

    # 3. Generate CA and Server Certificates
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout ca.key -out ca.crt -subj "/C=US/ST=Test/L=Test/O=Test CA/CN=Test Root CA"
    openssl req -new -nodes -newkey rsa:2048 -keyout server.key -out server.csr -subj "/C=US/ST=Test/L=Test/O=Test Server/CN=localhost"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -sha256

    # Remove keys to avoid clutter, keep only crt
    rm -f ca.key server.key server.csr ca.srl

    # 4. Create manifest.txt with one fake hash (app.py)
    CONFIG_HASH=$(sha256sum config.yaml | awk '{print $1}')
    SERVER_CRT_HASH=$(sha256sum server.crt | awk '{print $1}')
    CA_CRT_HASH=$(sha256sum ca.crt | awk '{print $1}')

    # Write to manifest
    echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa app.py" > manifest.txt
    echo "$CONFIG_HASH config.yaml" >> manifest.txt
    echo "$SERVER_CRT_HASH server.crt" >> manifest.txt
    echo "$CA_CRT_HASH ca.crt" >> manifest.txt

    chown -R user:user /home/user
    chmod -R 777 /home/user
