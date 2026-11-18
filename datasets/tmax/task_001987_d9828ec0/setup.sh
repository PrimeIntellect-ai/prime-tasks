#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.x509.oid import NameOID
import datetime

os.makedirs("/home/user", exist_ok=True)

# 1. Generate CA
ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Fake CA")])
ca_cert = x509.CertificateBuilder().subject_name(ca_subject).issuer_name(issuer).public_key(ca_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10)).sign(ca_key, hashes.SHA256())

# 2. Generate Dropper Cert
drop_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
drop_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Dropper")])
drop_cert = x509.CertificateBuilder().subject_name(drop_subject).issuer_name(ca_subject).public_key(drop_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10)).sign(ca_key, hashes.SHA256())

with open("/home/user/ca.crt", "wb") as f:
    f.write(ca_cert.public_bytes(serialization.Encoding.PEM))
with open("/home/user/dropper.crt", "wb") as f:
    f.write(drop_cert.public_bytes(serialization.Encoding.PEM))

# 3. Derive Key & Encrypt Data
fingerprint = drop_cert.fingerprint(hashes.SHA256()).hex()
aes_key = fingerprint[:32].encode('ascii')

plaintext = b"192.168.1.50\n10.0.5.12\n172.16.20.100\n"

md5_hash = hashlib.md5(plaintext).hexdigest()
with open("/home/user/config.md5", "w") as f:
    f.write(md5_hash)

iv = os.urandom(16)
padder = padding.PKCS7(128).padder()
padded_data = padder.update(plaintext) + padder.finalize()

cipher = Cipher(algorithms.AES(aes_key), modes.CBC(iv))
encryptor = cipher.encryptor()
ciphertext = encryptor.update(padded_data) + encryptor.finalize()

with open("/home/user/config.enc", "wb") as f:
    f.write(iv + ciphertext)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
