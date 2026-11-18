#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest cryptography Pillow

mkdir -p /app/fuzz_certs
mkdir -p /var/uploads

cat << 'EOF' > /app/setup.py
import os
import random
import datetime
from PIL import Image, ImageDraw
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.x509.oid import NameOID
from cryptography import x509

# Generate Image
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "TOKEN: a9f3b20c8d71", fill=(0,0,0))
img.save('/app/intercepted_upload.png')

# Generate Root CA
ca_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Root CA")])
ca_cert = x509.CertificateBuilder().subject_name(
    ca_subject
).issuer_name(
    ca_subject
).public_key(
    ca_private_key.public_key()
).serial_number(
    x509.random_serial_number()
).not_valid_before(
    datetime.datetime.utcnow()
).not_valid_after(
    datetime.datetime.utcnow() + datetime.timedelta(days=365)
).add_extension(
    x509.BasicConstraints(ca=True, path_length=None), critical=True,
).sign(ca_private_key, hashes.SHA256())

with open('/app/root_ca.pem', 'wb') as f:
    f.write(ca_cert.public_bytes(serialization.Encoding.PEM))

# Generate Fuzz Certs
for i in range(100):
    cert_type = random.choice(['valid', 'expired', 'unknown_ca', 'invalid'])
    cert_path = f'/app/fuzz_certs/cert_{i}.pem'

    if cert_type == 'invalid':
        with open(cert_path, 'w') as f:
            f.write("-----BEGIN CERTIFICATE-----\nINVALID\n-----END CERTIFICATE-----\n")
        continue

    client_key = rsa.generate_private_key(public_exponent=65537, key_size=1024)
    client_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Client")])

    builder = x509.CertificateBuilder().subject_name(
        client_subject
    ).public_key(
        client_key.public_key()
    ).serial_number(
        x509.random_serial_number()
    )

    if cert_type == 'expired':
        builder = builder.not_valid_before(datetime.datetime.utcnow() - datetime.timedelta(days=10)).not_valid_after(datetime.datetime.utcnow() - datetime.timedelta(days=5))
    else:
        builder = builder.not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=30))

    if cert_type == 'unknown_ca':
        fake_ca_key = rsa.generate_private_key(public_exponent=65537, key_size=1024)
        client_cert = builder.issuer_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"Fake CA")])).sign(fake_ca_key, hashes.SHA256())
    else:
        client_cert = builder.issuer_name(ca_subject).sign(ca_private_key, hashes.SHA256())

    with open(cert_path, 'wb') as f:
        f.write(client_cert.public_bytes(serialization.Encoding.PEM))
EOF

python3 /app/setup.py

cat << 'EOF' > /app/oracle_validator.py
import argparse
import sys
import os
import urllib.parse
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import datetime

def verify_cert(cert_path, ca_path):
    try:
        with open(ca_path, 'rb') as f:
            ca_cert = x509.load_pem_x509_certificate(f.read(), default_backend())
        with open(cert_path, 'rb') as f:
            client_cert = x509.load_pem_x509_certificate(f.read(), default_backend())

        now = datetime.datetime.utcnow()
        if now < client_cert.not_valid_before or now > client_cert.not_valid_after:
            return False

        if client_cert.issuer != ca_cert.subject:
            return False

        return True
    except Exception:
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--path', required=True)
    parser.add_argument('--token', required=True)
    parser.add_argument('--cert', required=True)
    args = parser.parse_args()

    if args.token != "a9f3b20c8d71":
        print("ERROR: INVALID_TOKEN")
        sys.exit(1)

    if not verify_cert(args.cert, "/app/root_ca.pem"):
        print("ERROR: INVALID_CERT")
        sys.exit(2)

    decoded_path = urllib.parse.unquote(args.path)
    base_dir = "/var/uploads"
    final_path = os.path.normpath(os.path.join(base_dir, decoded_path))

    if not final_path.startswith(base_dir + os.sep) and final_path != base_dir:
        print("ERROR: PATH_TRAVERSAL")
        sys.exit(3)

    print(f"SUCCESS: {final_path}")
    sys.exit(0)

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
