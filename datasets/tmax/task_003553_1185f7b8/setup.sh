#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        curl \
        zip \
        unzip \
        openssl \
        libssl-dev \
        libcjson-dev \
        build-essential \
        jq \
        xxd \
        coreutils

    pip3 install pytest flask pyjwt cryptography

    mkdir -p /app/keys /app/corpus/clean /app/corpus/evil /app/backend /app/issuer

    # Create wordlist
    echo "password" > /app/wordlist.txt
    echo "123456" >> /app/wordlist.txt
    echo "rotate2024!" >> /app/wordlist.txt
    for i in $(seq 4 100); do echo "word$i" >> /app/wordlist.txt; done

    # Generate certificates
    cd /tmp
    # New keys
    openssl genrsa -out root_ca.key 2048
    openssl req -x509 -new -nodes -key root_ca.key -sha256 -days 1024 -out root_ca.pem -subj "/C=US/ST=State/L=City/O=Org/CN=RootCA"
    openssl genrsa -out leaf_cert.key 2048
    openssl req -new -key leaf_cert.key -out leaf_cert.csr -subj "/C=US/ST=State/L=City/O=Org/CN=LeafCert"
    openssl x509 -req -in leaf_cert.csr -CA root_ca.pem -CAkey root_ca.key -CAcreateserial -out leaf_cert.pem -days 500 -sha256

    # Old keys
    openssl genrsa -out old_ca.key 2048
    openssl req -x509 -new -nodes -key old_ca.key -sha256 -days 1024 -out old_ca.pem -subj "/C=US/ST=State/L=City/O=Org/CN=OldRootCA"
    openssl genrsa -out old_leaf.key 2048
    openssl req -new -key old_leaf.key -out old_leaf.csr -subj "/C=US/ST=State/L=City/O=Org/CN=OldLeafCert"
    openssl x509 -req -in old_leaf.csr -CA old_ca.pem -CAkey old_ca.key -CAcreateserial -out old_leaf.pem -days 500 -sha256

    # Self-signed
    openssl genrsa -out self_signed.key 2048
    openssl req -x509 -new -nodes -key self_signed.key -sha256 -days 1024 -out self_signed.pem -subj "/C=US/ST=State/L=City/O=Org/CN=SelfSigned"

    zip -P "rotate2024!" /app/keys/new_creds.zip root_ca.pem leaf_cert.pem leaf_cert.key

    # Generate tokens
    cat << 'EOF' > gen_token.py
import sys, json, base64
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization

def b64url(data):
    if isinstance(data, str): data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

alg = sys.argv[1]
key_path = sys.argv[2]
out_path = sys.argv[3]
payload_msg = sys.argv[4]

header = {"alg": alg, "typ": "JWT"}
payload = {"data": payload_msg}

h = b64url(json.dumps(header))
p = b64url(json.dumps(payload))
msg = f"{h}.{p}".encode()

if alg == "none":
    sig = ""
else:
    with open(key_path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    sig_bytes = key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
    sig = b64url(sig_bytes)

with open(out_path, "w") as f:
    f.write(f"{h}.{p}.{sig}")
EOF

    python3 gen_token.py RS256 leaf_cert.key /app/corpus/clean/clean_1.tok "clean1"
    python3 gen_token.py RS256 leaf_cert.key /app/corpus/clean/clean_2.tok "clean2"
    python3 gen_token.py RS256 leaf_cert.key /app/corpus/clean/clean_3.tok "clean3"
    python3 gen_token.py RS256 leaf_cert.key /app/corpus/clean/clean_4.tok "clean4"
    python3 gen_token.py RS256 leaf_cert.key /app/corpus/clean/clean_5.tok "clean5"

    python3 gen_token.py none none /app/corpus/evil/evil_1.tok "evil1"
    python3 gen_token.py RS256 old_leaf.key /app/corpus/evil/evil_2.tok "evil2"
    python3 gen_token.py RS256 self_signed.key /app/corpus/evil/evil_3.tok "evil3"
    python3 gen_token.py none none /app/corpus/evil/evil_4.tok "evil4"
    python3 gen_token.py RS256 old_leaf.key /app/corpus/evil/evil_5.tok "evil5"

    # Save leaf cert locally for the issuer
    cp leaf_cert.key /app/issuer/leaf_cert.key

    rm -f root_ca.key root_ca.pem leaf_cert.key leaf_cert.csr leaf_cert.pem leaf_cert.srl
    rm -f old_ca.key old_ca.pem old_leaf.key old_leaf.csr old_leaf.pem old_leaf.srl
    rm -f self_signed.key self_signed.pem gen_token.py

    # Create Issuer
    cat << 'EOF' > /app/issuer/server.py
from flask import Flask
import os, json, base64
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization

app = Flask(__name__)

def b64url(data):
    if isinstance(data, str): data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

@app.route('/auth')
def auth():
    header = {"alg": "RS256", "typ": "JWT"}
    payload = {"user": "admin"}
    h = b64url(json.dumps(header))
    p = b64url(json.dumps(payload))
    msg = f"{h}.{p}".encode()

    with open("/app/issuer/leaf_cert.key", "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    sig_bytes = key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
    sig = b64url(sig_bytes)
    return f"{h}.{p}.{sig}"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    # Create Backend
    cat << 'EOF' > /app/backend/server.py
from flask import Flask, request
import subprocess, tempfile, os

app = Flask(__name__)

@app.route('/api/data')
def api_data():
    token = request.headers.get("Token")
    if not token:
        return "Missing Token", 401

    fd, path = tempfile.mkstemp()
    with os.fdopen(fd, 'w') as f:
        f.write(token)

    # Needs to be updated by the agent to use /app/validator
    # result = subprocess.run(["/app/validator", path])
    # if result.returncode == 0:
    #     os.remove(path)
    #     return "SECURE_DATA_ACCESSED"

    os.remove(path)
    return "UNAUTHORIZED", 401

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8082)
EOF

    # Create Start Script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service nginx start
python3 /app/issuer/server.py &
python3 /app/backend/server.py &
wait
EOF

    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
