#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-pil
pip3 install pytest pyjwt cryptography

mkdir -p /app/verifier/corpus/evil
mkdir -p /app/verifier/corpus/clean

cat << 'EOF' > /tmp/setup.py
import os
import jwt
import datetime
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.x509.oid import NameOID
from cryptography import x509
from PIL import Image, ImageDraw, ImageFont
import subprocess
import hashlib

HMAC_SECRET = "Sup3rS3cr3tHmacK3y2023!"

# Generate trusted key and cert
trusted_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u"trusted")])
trusted_cert = x509.CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(trusted_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10)).sign(trusted_key, hashes.SHA256())
trusted_cert_pem = trusted_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')
trusted_cert_b64 = "".join(trusted_cert_pem.splitlines()[1:-1])
trusted_fp = hashlib.sha256(trusted_cert.public_bytes(serialization.Encoding.DER)).hexdigest().upper()
trusted_fp_formatted = ":".join(trusted_fp[i:i+2] for i in range(0, len(trusted_fp), 2))

# Generate untrusted key and cert
untrusted_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
untrusted_cert = x509.CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(untrusted_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.utcnow()).not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=10)).sign(untrusted_key, hashes.SHA256())
untrusted_cert_b64 = "".join(untrusted_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8').splitlines()[1:-1])

# Generate video frames
os.makedirs("/tmp/frames", exist_ok=True)
for i in range(300):
    img = Image.new('RGB', (640, 480), color = 'black')
    if 150 <= i < 155:
        d = ImageDraw.Draw(img)
        d.text((10,10), f"HMAC_SECRET: {HMAC_SECRET}", fill=(255,255,255))
        d.text((10,50), f"TRUSTED_FINGERPRINT: {trusted_fp_formatted}", fill=(255,255,255))
    img.save(f"/tmp/frames/frame_{i:03d}.png")

subprocess.run(["ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frames/frame_%03d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/dashboard_recording.mp4"], check=True)

# Generate Clean Corpus
clean_dir = "/app/verifier/corpus/clean"
# 1. HS256, user, csp
t1 = jwt.encode({"role": "user", "csp": "default-src 'self'"}, HMAC_SECRET, algorithm="HS256")
with open(os.path.join(clean_dir, "clean1.txt"), "w") as f: f.write(t1)

# 2. RS256, admin, csp
t2 = jwt.encode({"role": "admin", "csp": "default-src 'self'"}, trusted_key, algorithm="RS256", headers={"x5c": [trusted_cert_b64]})
with open(os.path.join(clean_dir, "clean2.txt"), "w") as f: f.write(t2)

# Generate Evil Corpus
evil_dir = "/app/verifier/corpus/evil"
# 1. alg: none
t_evil1 = jwt.encode({"role": "user", "csp": "default-src 'self'"}, "", algorithm="none")
with open(os.path.join(evil_dir, "evil1.txt"), "w") as f: f.write(t_evil1)

# 2. HS256 admin
t_evil2 = jwt.encode({"role": "admin", "csp": "default-src 'self'"}, HMAC_SECRET, algorithm="HS256")
with open(os.path.join(evil_dir, "evil2.txt"), "w") as f: f.write(t_evil2)

# 3. RS256 untrusted
t_evil3 = jwt.encode({"role": "admin", "csp": "default-src 'self'"}, untrusted_key, algorithm="RS256", headers={"x5c": [untrusted_cert_b64]})
with open(os.path.join(evil_dir, "evil3.txt"), "w") as f: f.write(t_evil3)

# 4. missing csp
t_evil4 = jwt.encode({"role": "user"}, HMAC_SECRET, algorithm="HS256")
with open(os.path.join(evil_dir, "evil4.txt"), "w") as f: f.write(t_evil4)

# 5. invalid signature
t_evil5 = jwt.encode({"role": "user", "csp": "default-src 'self'"}, "wrongsecret", algorithm="HS256")
with open(os.path.join(evil_dir, "evil5.txt"), "w") as f: f.write(t_evil5)

EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
