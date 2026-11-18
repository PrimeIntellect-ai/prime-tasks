#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import base64
import os
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import datetime

# 1. Generate cert.pem with the secret key in the Organization field
secret_key = b"SeCrEtKeY1234567" # 16 bytes

private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
)

subject = issuer = x509.Name([
    x509.NameAttribute(NameOID.COUNTRY_NAME, u"US"),
    x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, u"California"),
    x509.NameAttribute(NameOID.LOCALITY_NAME, u"San Francisco"),
    x509.NameAttribute(NameOID.ORGANIZATION_NAME, secret_key.decode('utf-8')),
    x509.NameAttribute(NameOID.COMMON_NAME, u"internal.server.local"),
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

with open("/home/user/cert.pem", "wb") as f:
    f.write(cert.public_bytes(serialization.Encoding.PEM))

# 2. Generate traffic.json
def encrypt_payload(plaintext, key):
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(plaintext.encode()) + padder.finalize()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(padded_data) + encryptor.finalize()
    return base64.b64encode(iv + ciphertext).decode('utf-8')

traffic = [
    {
        "src_ip": "192.168.1.100",
        "dst_ip": "8.8.8.8",
        "method": "GET",
        "headers": {
            "User-Agent": "curl/7.68.0",
            "X-Telemetry-Data": encrypt_payload("Normal telemetry data without signature.", secret_key)
        }
    },
    {
        "src_ip": "10.0.5.55",
        "dst_ip": "1.2.3.4",
        "method": "POST",
        "headers": {
            "User-Agent": "Mozilla/5.0",
            "X-Telemetry-Data": encrypt_payload("Data leak: [C2_EXFIL_START] root:x:0:0...", secret_key)
        }
    },
    {
        "src_ip": "172.16.0.4",
        "dst_ip": "5.6.7.8",
        "method": "POST",
        "headers": {
            "User-Agent": "Mozilla/5.0",
            "X-Telemetry-Data": encrypt_payload("[C2_EXFIL_START] shadow file contents...", secret_key)
        }
    },
    {
        "src_ip": "192.168.1.105",
        "dst_ip": "9.9.9.9",
        "method": "GET",
        "headers": {
            "User-Agent": "wget"
        }
    }
]

with open("/home/user/traffic.json", "w") as f:
    json.dump(traffic, f, indent=4)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
