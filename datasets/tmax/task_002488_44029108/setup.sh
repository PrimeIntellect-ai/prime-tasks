#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak zip gcc binutils
    pip3 install pytest cryptography

    mkdir -p /app

    # 1. Generate audio file
    espeak -w /app/voicemail.wav "Hey, I set the archive password. It's OmegaUpload followed by four random digits."

    # 2. Create slow_cracker.py
    cat << 'EOF' > /app/slow_cracker.py
import sys
import hashlib

def main():
    if len(sys.argv) < 2:
        return
    target = sys.argv[1].strip()
    prefix = "OmegaUpload"
    for i in range(10000):
        # Artificial slowdown
        for _ in range(500):
            pass
        guess = f"{prefix}{i:04d}"
        if hashlib.sha256(guess.encode()).hexdigest() == target:
            print(guess)
            return

if __name__ == "__main__":
    main()
EOF

    # 3. Generate target hash
    echo -n "OmegaUpload7391" | sha256sum | awk '{print $1}' > /app/target_hash.txt

    # 4. Generate certificates using Python
    mkdir -p /tmp/certs
    cat << 'EOF' > /tmp/certs/gen_certs.py
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.x509.oid import NameOID
from cryptography import x509
import datetime

def gen_cert(cn, issuer_name, issuer_key, days_valid, is_ca=False):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])

    cert_builder = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer_name if issuer_name else subject
    ).public_key(
        key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.utcnow() - datetime.timedelta(days=365)
    ).not_valid_after(
        datetime.datetime.utcnow() + datetime.timedelta(days=days_valid)
    )

    if is_ca:
        cert_builder = cert_builder.add_extension(
            x509.BasicConstraints(ca=True, path_length=None), critical=True
        )

    cert = cert_builder.sign(issuer_key if issuer_key else key, hashes.SHA256())
    return cert, key, subject

root_cert, root_key, root_name = gen_cert("EvilCorp Root CA", None, None, 3650, True)
int_cert, int_key, int_name = gen_cert("EvilCorp Intermediate CA G2", root_name, root_key, -10, True) # expired
leaf_cert, leaf_key, leaf_name = gen_cert("evilcorp.com", int_name, int_key, 365, False)

with open("/tmp/certs/chain.pem", "wb") as f:
    f.write(leaf_cert.public_bytes(serialization.Encoding.PEM))
    f.write(int_cert.public_bytes(serialization.Encoding.PEM))
    f.write(root_cert.public_bytes(serialization.Encoding.PEM))
EOF

    python3 /tmp/certs/gen_certs.py

    # 5. Create dummy ELF binary with embedded endpoint and certs
    cd /tmp/certs
    ld -r -b binary -o chain.o chain.pem

    cat << 'EOF' > /tmp/daemon.c
#include <stdio.h>
const char* endpoint = "/api/v2/internal/sys_upload_traversal_unsafe";
int main() {
    printf("Daemon running...\n");
    return 0;
}
EOF

    gcc /tmp/daemon.c chain.o -o /app/uploader_daemon

    # 6. Zip the payload
    cd /app
    zip -P OmegaUpload7391 payload.zip uploader_daemon
    rm uploader_daemon
    rm -rf /tmp/certs /tmp/daemon.c

    # 7. Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
