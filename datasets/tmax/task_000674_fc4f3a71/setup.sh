#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import base64
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import datetime

def generate_cert_b64(cn):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, cn),
    ])
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        private_key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.utcnow()
    ).not_valid_after(
        datetime.datetime.utcnow() + datetime.timedelta(days=10)
    ).sign(private_key, hashes.SHA256())

    pem = cert.public_bytes(serialization.Encoding.PEM)
    return base64.b64encode(pem).decode('utf-8')

cert1 = generate_cert_b64("malicious.hacker.local")
cert2 = generate_cert_b64("exploit.test.domain")
cert3 = generate_cert_b64("ignored.domain.com")

log_content = f"""192.168.1.10 - - [10/Oct/2023:13:55:36 -0000] "GET / HTTP/1.1" 200 1234 "-" "Mozilla/5.0"
10.0.0.5 - - [10/Oct/2023:13:56:01 -0000] "GET /vulnerable HTTP/1.1" 500 532 "-" "{cert1}"
192.168.1.11 - - [10/Oct/2023:13:56:15 -0000] "GET / HTTP/1.1" 404 234 "-" "Mozilla/5.0"
172.16.0.42 - - [10/Oct/2023:13:57:22 -0000] "POST /api HTTP/1.1" 500 532 "-" "{cert2}"
10.0.0.8 - - [10/Oct/2023:13:58:00 -0000] "GET /vulnerable HTTP/1.1" 200 532 "-" "{cert3}"
"""

with open("/home/user/access.log", "w") as f:
    f.write(log_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
