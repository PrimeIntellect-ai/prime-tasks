#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak openssl coreutils gawk
    pip3 install pytest flask

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/audit/crypto_assets/certs
    mkdir -p /home/user/audit/crypto_assets/ssh
    mkdir -p /home/user/audit/webapp/backend
    mkdir -p /home/user/audit/traffic_corpus/evil
    mkdir -p /home/user/audit/traffic_corpus/clean

    # Phase 1: Audio Fixture
    espeak -w /app/intercepted_call.wav "The server is prepped. The backdoor passphrase is crimson_sunrise_42. Do not lose it."

    # Phase 2: Cryptographic Assets
    # Create rogue CA protected by passphrase
    openssl genrsa -aes256 -passout pass:crimson_sunrise_42 -out /home/user/audit/crypto_assets/certs/rogue_ca.key 2048
    openssl req -x509 -new -nodes -key /home/user/audit/crypto_assets/certs/rogue_ca.key -passin pass:crimson_sunrise_42 -sha256 -days 1024 -out /home/user/audit/crypto_assets/certs/rogue_ca.crt -subj "/CN=RogueCA"

    # Create rogue cert chain4.pem signed by rogue CA
    openssl genrsa -out /tmp/rogue.key 2048
    openssl req -new -key /tmp/rogue.key -out /tmp/rogue.csr -subj "/CN=RogueCert"
    openssl x509 -req -in /tmp/rogue.csr -CA /home/user/audit/crypto_assets/certs/rogue_ca.crt -CAkey /home/user/audit/crypto_assets/certs/rogue_ca.key -passin pass:crimson_sunrise_42 -CAcreateserial -out /tmp/rogue.crt -days 500 -sha256
    cat /tmp/rogue.crt /home/user/audit/crypto_assets/certs/rogue_ca.crt > /home/user/audit/crypto_assets/certs/chain4.pem

    # Create other benign certs
    for i in 1 2 3 5; do
        openssl req -x509 -newkey rsa:2048 -keyout /tmp/k.pem -out /home/user/audit/crypto_assets/certs/chain${i}.pem -days 365 -nodes -subj "/CN=Normal${i}"
    done

    # Create SSH keys
    HASH=$(echo -n "crimson_sunrise_42" | sha256sum | awk '{print $1}')
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... $HASH" > /home/user/audit/crypto_assets/ssh/id_ed25519_rogue.pub
    for i in 1 2 3 4; do
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user$i" > /home/user/audit/crypto_assets/ssh/id_ed25519_$i.pub
    done

    # Phase 3: Vulnerability Setup (CWE-22)
    cat << 'EOF' > /home/user/audit/webapp/backend/app.py
from flask import Flask, request, send_file
import os

app = Flask(__name__)

@app.route('/download')
def download():
    filename = request.args.get('file')
    # Vulnerable to Path Traversal (CWE-22)
    return send_file(os.path.join('/var/www/html', filename))
EOF

    # Phase 4: Adversarial Corpus Verifier
    echo "../../../etc/passwd" > /home/user/audit/traffic_corpus/evil/payload1.txt
    echo "%2e%2e%2f%2e%2e%2fetc%2fpasswd" > /home/user/audit/traffic_corpus/evil/payload2.txt

    echo "user_profile.png" > /home/user/audit/traffic_corpus/clean/req1.txt
    echo "index.html" > /home/user/audit/traffic_corpus/clean/req2.txt
    echo "report_2023.pdf" > /home/user/audit/traffic_corpus/clean/req3.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
