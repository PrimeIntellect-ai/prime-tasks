#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/secure_service/certs

    # Generate legitimate dummy key and cert
    python3 -c "
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.x509 import CertificateBuilder, Name, NameAttribute
from cryptography.x509.oid import NameOID
import datetime

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
subject = issuer = Name([NameAttribute(NameOID.COMMON_NAME, u'LegitService')])
cert = CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(key.public_key()).serial_number(1).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=365)).sign(key, hashes.SHA256())

with open('/home/user/secure_service/certs/trust.pem', 'wb') as f:
    f.write(cert.public_bytes(serialization.Encoding.PEM))
"

    # Set vulnerable permissions
    chmod 666 /home/user/secure_service/certs/trust.pem

    # Create the verify_and_run.py script
    cat << 'EOF' > /home/user/secure_service/verify_and_run.py
import sys
import json
import base64
from cryptography.x509 import load_pem_x509_certificates
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes
from cryptography.exceptions import InvalidSignature

if len(sys.argv) != 2:
    print("Usage: python verify_and_run.py <payload.json>")
    sys.exit(1)

try:
    with open(sys.argv[1], 'r') as f:
        payload = json.load(f)

    code_b64 = payload['code']
    signature = base64.b64decode(payload['signature'])
    code_bytes = base64.b64decode(code_b64)

    with open('/home/user/secure_service/certs/trust.pem', 'rb') as f:
        trust_pem = f.read()

    certs = load_pem_x509_certificates(trust_pem)

    verified = False
    for cert in certs:
        public_key = cert.public_key()
        try:
            public_key.verify(
                signature,
                code_b64.encode('utf-8'),
                padding.PKCS1v15(),
                hashes.SHA256()
            )
            verified = True
            break
        except InvalidSignature:
            continue

    if not verified:
        print("Verification failed.")
        sys.exit(1)

    # Execute the sandboxed code
    exec(code_bytes.decode('utf-8'))

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF

    chmod 755 /home/user/secure_service/verify_and_run.py

    chmod -R 777 /home/user
