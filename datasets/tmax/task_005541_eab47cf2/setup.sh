#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest PyJWT cryptography

    mkdir -p /home/user/inspect/ca

    cat << 'EOF' > /tmp/setup.py
import os
import json
import jwt
import datetime
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import hashes
from cryptography.x509.oid import NameOID
from cryptography import x509

def generate_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)

def generate_cert(subject_name, issuer_name, private_key, issuer_key, is_ca=False):
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject_name)])
    issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, issuer_name)])
    cert_builder = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        private_key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.utcnow() - datetime.timedelta(days=1)
    ).not_valid_after(
        datetime.datetime.utcnow() + datetime.timedelta(days=365)
    )
    if is_ca:
        cert_builder = cert_builder.add_extension(
            x509.BasicConstraints(ca=True, path_length=None), critical=True
        )
    return cert_builder.sign(issuer_key, hashes.SHA256())

def to_pem(cert):
    return cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')

def key_to_pem(key, public=False):
    if public:
        return key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode('utf-8')
    else:
        return key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        ).decode('utf-8')

root_key = generate_key()
root_cert = generate_cert(u"Root CA", u"Root CA", root_key, root_key, is_ca=True)

int_key = generate_key()
int_cert = generate_cert(u"Int CA", u"Root CA", int_key, root_key, is_ca=True)

rogue_key = generate_key()
rogue_cert = generate_cert(u"Rogue CA", u"Rogue CA", rogue_key, rogue_key, is_ca=True)

leaf1_key = generate_key()
leaf1_cert = generate_cert(u"Leaf 1", u"Int CA", leaf1_key, int_key)

leaf2_key = generate_key()
leaf2_cert = generate_cert(u"Leaf 2", u"Int CA", leaf2_key, int_key)

rogue_leaf_key = generate_key()
rogue_leaf_cert = generate_cert(u"Rogue Leaf", u"Rogue CA", rogue_leaf_key, rogue_key)

jwt_key = generate_key()
jwt_priv_pem = key_to_pem(jwt_key)
jwt_pub_pem = key_to_pem(jwt_key, public=True)

rogue_jwt_key = generate_key()
rogue_jwt_priv_pem = key_to_pem(rogue_jwt_key)

payload = {"user": "admin"}
valid_jwt_1 = jwt.encode(payload, jwt_priv_pem, algorithm="RS256")
valid_jwt_2 = jwt.encode(payload, jwt_priv_pem, algorithm="RS256")
invalid_jwt_1 = jwt.encode(payload, rogue_jwt_priv_pem, algorithm="RS256")

logs = [
    {"session_id": "alpha_101", "server_cert": to_pem(leaf1_cert), "auth_token": valid_jwt_1},
    {"session_id": "bravo_202", "server_cert": to_pem(rogue_leaf_cert), "auth_token": valid_jwt_2},
    {"session_id": "charlie_303", "server_cert": to_pem(leaf2_cert), "auth_token": invalid_jwt_1},
    {"session_id": "delta_404", "server_cert": to_pem(leaf2_cert), "auth_token": valid_jwt_2}
]

with open("/home/user/inspect/ca/root.pem", "w") as f:
    f.write(to_pem(root_cert))
with open("/home/user/inspect/ca/intermediate.pem", "w") as f:
    f.write(to_pem(int_cert))
with open("/home/user/inspect/jwt_public.pem", "w") as f:
    f.write(jwt_pub_pem)
with open("/home/user/inspect/traffic_logs.json", "w") as f:
    json.dump(logs, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
