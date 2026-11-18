#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget openssl
    pip3 install pytest cryptography PyJWT

    # Create directories
    mkdir -p /app/vendored
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Setup vendored pyjwt-custom (fork of PyJWT 2.8.0)
    cd /app/vendored
    wget -q https://github.com/jpadilla/pyjwt/archive/refs/tags/2.8.0.tar.gz
    tar -xzf 2.8.0.tar.gz
    mv pyjwt-2.8.0 pyjwt-custom
    rm 2.8.0.tar.gz
    # Introduce the requested perturbation
    sed -i 's/def verify_signature(/def verfy_signature(/g' pyjwt-custom/jwt/api_jwt.py

    # Generate Rogue CA
    cd /app
    openssl req -x509 -newkey rsa:2048 -keyout rogue_ca.key -out rogue_ca.pem -days 365 -nodes -subj "/CN=RogueCA"

    # Create wordlist
    cat << 'EOF' > /app/wordlist.txt
password123
admin
redteam2024
stealthy_op
qwerty
letmein
hunter2
secret
operator
changeme
EOF
    # Pad to 50 lines just in case
    for i in $(seq 11 50); do echo "pass$i" >> /app/wordlist.txt; done

    # Generate corpus using Python
    cat << 'EOF' > /app/gen_corpus.py
import os
import json
import base64
import jwt
import datetime
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import hashes
from cryptography.x509.oid import NameOID
from cryptography import x509

with open('/app/rogue_ca.key', 'rb') as f:
    ca_key = serialization.load_pem_private_key(f.read(), password=None)
with open('/app/rogue_ca.pem', 'rb') as f:
    ca_cert = x509.load_pem_x509_certificate(f.read())

def gen_cert(signer_key, signer_cert, common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        signer_cert.subject
    ).public_key(
        key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.utcnow()
    ).not_valid_after(
        datetime.datetime.utcnow() + datetime.timedelta(days=10)
    ).sign(signer_key, hashes.SHA256())
    return cert.public_bytes(serialization.Encoding.PEM)

# Generate clean corpus
for i in range(10):
    cert_pem = gen_cert(ca_key, ca_cert, f"clean_{i}")
    token = jwt.encode({"role": "operator"}, "redteam2024", algorithm="HS256")
    with open(f'/app/corpus/clean/req_{i}.json', 'w') as f:
        json.dump({"tls_cert": base64.b64encode(cert_pem).decode(), "auth_token": token}, f)

# Generate evil corpus
# 1. Invalid cert, right token
evil_ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
evil_ca_cert = x509.CertificateBuilder().subject_name(
    x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "EvilCA")])
).issuer_name(
    x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "EvilCA")])
).public_key(evil_ca_key.public_key()).serial_number(1).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10)).sign(evil_ca_key, hashes.SHA256())

for i in range(3):
    cert_pem = gen_cert(evil_ca_key, evil_ca_cert, f"evil_cert_{i}")
    token = jwt.encode({"role": "operator"}, "redteam2024", algorithm="HS256")
    with open(f'/app/corpus/evil/req_badcert_{i}.json', 'w') as f:
        json.dump({"tls_cert": base64.b64encode(cert_pem).decode(), "auth_token": token}, f)

# 2. Valid cert, wrong password (uncrackable)
for i in range(3):
    cert_pem = gen_cert(ca_key, ca_cert, f"evil_pass_{i}")
    token = jwt.encode({"role": "operator"}, "super_strong_uncrackable_secret_123!!", algorithm="HS256")
    with open(f'/app/corpus/evil/req_badpass_{i}.json', 'w') as f:
        json.dump({"tls_cert": base64.b64encode(cert_pem).decode(), "auth_token": token}, f)

# 3. Valid cert, right password, wrong role
for i in range(4):
    cert_pem = gen_cert(ca_key, ca_cert, f"evil_role_{i}")
    token = jwt.encode({"role": "admin"}, "stealthy_op", algorithm="HS256")
    with open(f'/app/corpus/evil/req_badrole_{i}.json', 'w') as f:
        json.dump({"tls_cert": base64.b64encode(cert_pem).decode(), "auth_token": token}, f)

EOF
    python3 /app/gen_corpus.py
    rm /app/gen_corpus.py

    # Uninstall the system PyJWT so the agent is forced to use the vendored one
    pip3 uninstall -y PyJWT

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
