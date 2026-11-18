#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl xxd sqlite3
    pip3 install pytest flask

    mkdir -p /home/user/incident_response/auth_service
    mkdir -p /home/user/incident_response/tokens
    mkdir -p /home/user/incident_response/keys
    mkdir -p /home/user/incident_response/certs

    # Phase 1 Setup
    cat << 'EOF' > /home/user/incident_response/wordlist.txt
admin123
company2023!
hunter2
password123
SecurityMatter$
EOF

    cat << 'EOF' > /home/user/incident_response/admin_hashes.txt
alice:8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918
bob:1a067ec841b8979fcabed4480d0d82992b8d002f23246ebcfd6a5496d0ea43b1
EOF

    # Phase 2 Setup
    cat << 'EOF' > /home/user/incident_response/auth_service/app.py
from flask import Flask, request, redirect, jsonify
import sqlite3

app = Flask(__name__)

def get_db():
    conn = sqlite3.connect('users.db')
    return conn

@app.route('/login', methods=['POST'])
def login():
    username = request.form.get('username')
    password = request.form.get('password')
    next_url = request.args.get('next', '/')

    conn = get_db()
    cursor = conn.cursor()
    # Vulnerability 1: SQL Injection
    query = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
    cursor.execute(query)
    user = cursor.fetchone()

    if user:
        # Vulnerability 2: Open Redirect
        return redirect(next_url)
    return jsonify({"error": "Invalid credentials"}), 401
EOF

    # Phase 3 Setup
    openssl rand -out /home/user/incident_response/keys/old_key.bin 32
    openssl rand -out /home/user/incident_response/keys/old_iv.bin 16
    openssl rand -out /home/user/incident_response/keys/new_key.bin 32
    openssl rand -out /home/user/incident_response/keys/new_iv.bin 16

    echo -n "SuperSecretMasterToken999" > /tmp/plaintext_token.txt
    openssl enc -aes-256-cbc -in /tmp/plaintext_token.txt -out /home/user/incident_response/tokens/master_token.enc \
        -K $(xxd -p -c 32 /home/user/incident_response/keys/old_key.bin) \
        -iv $(xxd -p -c 16 /home/user/incident_response/keys/old_iv.bin)

    # Phase 4 Setup
    cd /home/user/incident_response/certs
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout rootCA.key -out rootCA.pem -subj "/CN=Trusted-Root-CA"

    openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr -subj "/CN=Compromised-Intermediate-CA"
    cat << 'EOF' > v3_int.ext
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF
    openssl x509 -req -in int.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out int.pem -days -1 -extfile v3_int.ext

    openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=service.local"
    openssl x509 -req -in leaf.csr -CA int.pem -CAkey int.key -CAcreateserial -out leaf.pem -days 365

    cat leaf.pem int.pem > chain.pem
    cd /

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
