#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest cryptography Pillow

    mkdir -p /app/corpus/evil /app/corpus/clean /home/user

    cat << 'EOF' > /app/setup.py
import os
import json
import random
import datetime
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.x509.oid import NameOID
from cryptography import x509
from PIL import Image, ImageDraw, ImageFont

def generate_cert(name, issuer_name, issuer_key, is_ca=False):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)])
    issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, issuer_name)])

    builder = x509.CertificateBuilder()
    builder = builder.subject_name(subject)
    builder = builder.issuer_name(issuer)
    builder = builder.public_key(private_key.public_key())
    builder = builder.serial_number(x509.random_serial_number())
    builder = builder.not_valid_before(datetime.datetime.utcnow() - datetime.timedelta(days=1))
    builder = builder.not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=365))

    if is_ca:
        builder = builder.add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)

    cert = builder.sign(issuer_key if issuer_key else private_key, hashes.SHA256())
    return private_key, cert

# Generate Root CA
root_key, root_cert = generate_cert("Root CA", "Root CA", None, is_ca=True)
with open("/app/root_ca.pem", "wb") as f:
    f.write(root_cert.public_bytes(serialization.Encoding.PEM))

# Generate Intermediate CA
int_key, int_cert = generate_cert("Intermediate CA", "Root CA", root_key, is_ca=True)

# Generate Bad Intermediate CA (self-signed)
bad_int_key, bad_int_cert = generate_cert("Bad Intermediate CA", "Bad Intermediate CA", None, is_ca=True)

for i in range(50):
    # Clean
    client_key, client_cert = generate_cert(f"Client {i}", "Intermediate CA", int_key)
    clean_data = {
        "target_path": f"uploads/user{i}/profile.jpg",
        "client_cert_pem": client_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8'),
        "intermediate_cert_pem": int_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')
    }
    with open(f"/app/corpus/clean/req_{i}.json", "w") as f:
        json.dump(clean_data, f)

    # Evil
    evil_type = i % 5
    if evil_type == 0:
        target_path = f"../uploads/user{i}/profile.jpg"
        c_cert, i_cert = client_cert, int_cert
    elif evil_type == 1:
        target_path = "/etc/shadow"
        c_cert, i_cert = client_cert, int_cert
    elif evil_type == 2:
        target_path = f"uploads/user{i}/profile.jpg"
        _, c_cert = generate_cert(f"Client {i}", "Intermediate CA", bad_int_key) # Bad sig
        i_cert = int_cert
    elif evil_type == 3:
        target_path = f"uploads/user{i}/profile.jpg"
        _, c_cert = generate_cert(f"Client {i}", "Bad Intermediate CA", bad_int_key)
        i_cert = bad_int_cert
    else:
        target_path = f"uploads/user{i}/shell.php"
        c_cert, i_cert = client_cert, int_cert

    evil_data = {
        "target_path": target_path,
        "client_cert_pem": c_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8'),
        "intermediate_cert_pem": i_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')
    }
    with open(f"/app/corpus/evil/req_{i}.json", "w") as f:
        json.dump(evil_data, f)

# Generate Video
logs = [
    "10:05:01 POST /upload?path=../../../etc/passwd - 192.168.1.105",
    "10:05:03 POST /upload?path=images/test.png - 192.168.1.100",
    "10:05:05 POST /upload?path=../uploads/admin_key - 10.0.0.52"
]

os.makedirs("/app/frames", exist_ok=True)
for i, log in enumerate(logs):
    img = Image.new('RGB', (800, 100), color = (0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((10, 40), log, fill=(255, 255, 255))
    for j in range(30): # 1 sec at 30fps
        img.save(f"/app/frames/frame_{i*30+j:04d}.png")

os.system("ffmpeg -framerate 30 -i /app/frames/frame_%04d.png -c:v libx264 -pix_fmt yuv420p /app/upload_logs.mp4")
EOF

    python3 /app/setup.py
    rm -rf /app/frames /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
