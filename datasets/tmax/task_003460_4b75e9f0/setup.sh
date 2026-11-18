#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak openssl
    pip3 install pytest cryptography

    mkdir -p /app/evidence /app/corpus/clean /app/corpus/evil

    # Generate audio evidence
    espeak -w /app/evidence/intercept.wav "We have successfully planted the rogue certificates. Remember, you can identify our malicious certificates because they meet at least one of these three conditions: the Issuer Organization Name is exactly PwnedLtd, the certificate signature algorithm uses MD5, or the certificate file has world-writable permissions."

    # Create an openssl config to enable legacy provider for MD5
    cat << 'EOF' > /tmp/openssl_legacy.cnf
openssl_conf = openssl_init

[openssl_init]
providers = provider_sect

[provider_sect]
default = default_sect
legacy = legacy_sect

[default_sect]
activate = 1

[legacy_sect]
activate = 1
EOF

    # Python script to generate the certificates
    cat << 'EOF' > /tmp/gen_certs.py
import os
import subprocess
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import datetime

def gen_cert_crypto(path, org_name, is_evil_perms=False):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, org_name),
    ])
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.utcnow()
    ).not_valid_after(
        datetime.datetime.utcnow() + datetime.timedelta(days=10)
    ).sign(key, hashes.SHA256())

    with open(path, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))

    if is_evil_perms:
        os.chmod(path, 0o777)
    else:
        os.chmod(path, 0o644)

def gen_cert_md5(path):
    # Use openssl with legacy provider to generate MD5 signed cert
    env = os.environ.copy()
    env["OPENSSL_CONF"] = "/tmp/openssl_legacy.cnf"
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", "/dev/null", "-out", path,
        "-days", "365", "-nodes", "-subj", "/O=AcmeCorp", "-md5"
    ], env=env, stderr=subprocess.DEVNULL)
    os.chmod(path, 0o644)

for i in range(10):
    gen_cert_crypto(f"/app/corpus/clean/clean_{i}.pem", "AcmeCorp")

for i in range(5):
    gen_cert_crypto(f"/app/corpus/evil/evil_org_{i}.pem", "PwnedLtd")

for i in range(5):
    gen_cert_md5(f"/app/corpus/evil/evil_md5_{i}.pem")

for i in range(5):
    gen_cert_crypto(f"/app/corpus/evil/evil_perms_{i}.pem", "AcmeCorp", is_evil_perms=True)
EOF

    python3 /tmp/gen_certs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
