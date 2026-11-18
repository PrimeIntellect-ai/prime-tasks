#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography pyjwt

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/certs

    cat << 'EOF' > /home/user/access.log
[2023-10-01 10:00:00] 192.168.1.50 GET /api/data "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGVzdCJ9.signature123"
[2023-10-01 10:05:00] 10.0.0.5 GET /admin "Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoic3VwZXJ1c2VyIn0."
[2023-10-01 10:10:00] 172.16.0.10 POST /api/upload "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGVzdDIifQ.signature456"
[2023-10-01 10:15:00] 192.168.1.99 GET /admin/settings "Bearer eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiaGFja2VyIn0."
[2023-10-01 10:20:00] 10.0.0.5 GET /admin/logs "Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoic3VwZXJ1c2VyIn0."
EOF

    cat << 'EOF' > /tmp/gen_certs.py
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.x509 import CertificateBuilder, Name, NameAttribute, random_serial_number, BasicConstraints
from cryptography.x509.oid import NameOID
import datetime

def gen_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)

root_key = gen_key()
int_key = gen_key()
leaf_key = gen_key()
fake_int_key = gen_key()

def build_cert(subject_name, issuer_name, subject_key, issuer_key, is_ca=False):
    subject = Name([NameAttribute(NameOID.COMMON_NAME, subject_name)])
    issuer = Name([NameAttribute(NameOID.COMMON_NAME, issuer_name)])
    builder = CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(subject_key.public_key()).serial_number(random_serial_number()).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10))
    if is_ca:
        builder = builder.add_extension(BasicConstraints(ca=True, path_length=None), critical=True)
    return builder.sign(issuer_key, hashes.SHA256())

root_cert = build_cert(u"Root", u"Root", root_key, root_key, True)
int_cert = build_cert(u"Int", u"Root", int_key, root_key, True)
leaf_cert = build_cert(u"Leaf", u"Int", leaf_key, fake_int_key, False)

with open("/home/user/certs/server_chain.pem", "wb") as f:
    f.write(leaf_cert.public_bytes(serialization.Encoding.PEM))
    f.write(int_cert.public_bytes(serialization.Encoding.PEM))
    f.write(root_cert.public_bytes(serialization.Encoding.PEM))
EOF

    python3 /tmp/gen_certs.py
    rm /tmp/gen_certs.py

    chmod -R 777 /home/user
