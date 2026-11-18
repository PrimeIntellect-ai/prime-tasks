#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest cryptography PyJWT

    useradd -m -s /bin/bash user || true

    cd /home/user
    mkdir -p setup_ca
    cd setup_ca

    cat << 'EOF' > generate_artifacts.py
import datetime
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import hashes
from cryptography.x509.oid import NameOID
from cryptography import x509
import jwt

# 1. Generate Root CA
root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
root_subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Root CA")])
root_cert = x509.CertificateBuilder().subject_name(
    root_subject
).issuer_name(
    issuer
).public_key(
    root_key.public_key()
).serial_number(
    x509.random_serial_number()
).not_valid_before(
    datetime.datetime.utcnow()
).not_valid_after(
    datetime.datetime.utcnow() + datetime.timedelta(days=365)
).add_extension(
    x509.BasicConstraints(ca=True, path_length=None), critical=True
).sign(root_key, hashes.SHA256())

# 2. Generate Leaf Cert
leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
leaf_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Leaf App Cert")])
leaf_cert = x509.CertificateBuilder().subject_name(
    leaf_subject
).issuer_name(
    root_subject
).public_key(
    leaf_key.public_key()
).serial_number(
    x509.random_serial_number()
).not_valid_before(
    datetime.datetime.utcnow()
).not_valid_after(
    datetime.datetime.utcnow() + datetime.timedelta(days=365)
).add_extension(
    x509.BasicConstraints(ca=False, path_length=None), critical=True
).sign(root_key, hashes.SHA256())

# Write cert chain (Leaf then Root)
with open("chain.pem", "wb") as f:
    f.write(leaf_cert.public_bytes(serialization.Encoding.PEM))
    f.write(root_cert.public_bytes(serialization.Encoding.PEM))

# 3. Generate JWT
private_key_pem = leaf_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.TraditionalOpenSSL,
    encryption_algorithm=serialization.NoEncryption()
)
token = jwt.encode({"sub": "deploy-agent-8842"}, private_key_pem, algorithm="RS256")
with open("token.txt", "w") as f:
    f.write(token)
EOF

    python3 generate_artifacts.py

    cat << 'EOF' > dummy.c
int main() { return 0; }
EOF
    gcc dummy.c -o raw.elf

    objcopy --add-section .cert_chain=chain.pem --set-section-flags .cert_chain=readonly \
            --add-section .auth_token=token.txt --set-section-flags .auth_token=readonly \
            raw.elf /home/user/target_binary.elf

    cd /home/user
    rm -rf setup_ca

    chmod -R 777 /home/user
