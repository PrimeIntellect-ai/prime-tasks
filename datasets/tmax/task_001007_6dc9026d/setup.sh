#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_env.py
import os
import hashlib
from cryptography.fernet import Fernet
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import datetime

# 1. Generate key and encrypt config
key = Fernet.generate_key()
with open('/home/user/.secret_key', 'wb') as f:
    f.write(key)

plaintext = b'{"db_host": "secure-db.local", "port": 5432, "feature_flag": true}'
f = Fernet(key)
ciphertext = f.encrypt(plaintext)

with open('/home/user/config.enc', 'wb') as f:
    f.write(ciphertext)

# 2. Hash
sha256_hash = hashlib.sha256(plaintext).hexdigest()
with open('/home/user/config.sha256', 'w') as f:
    f.write(sha256_hash)

# 3. Generate Cert
private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"deployment.local")])
cert = x509.CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(private_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10)).sign(private_key, hashes.SHA256())

with open('/home/user/server.crt', 'wb') as f:
    f.write(cert.public_bytes(serialization.Encoding.PEM))

EOF

    python3 /home/user/setup_env.py
    rm /home/user/setup_env.py

    cat << 'EOF' > /home/user/deploy.py
import sys
from cryptography.fernet import Fernet

def main():
    if len(sys.argv) < 2:
        print("Usage: deploy.py <key>")
        sys.exit(1)

    key = sys.argv[1].encode()
    f = Fernet(key)

    with open('/home/user/config.enc', 'rb') as file:
        ciphertext = file.read()

    plaintext = f.decrypt(ciphertext).decode('utf-8')

    html = f"<html><body><h1>Deployment Report</h1><p>Config: {plaintext}</p></body></html>"
    with open('/home/user/insecure_report.html', 'w') as file:
        file.write(html)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
