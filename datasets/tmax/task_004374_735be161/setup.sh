#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg openssl fonts-liberation
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -keyout /app/ca.key -out /app/ca.pem -days 365 -nodes -subj "/CN=RootCA"

    # Generate Video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=text='SECRET_HMAC_KEY=R3dT3am\!2024':x=50:y=50:fontsize=24:fontcolor=white:enable='between(t,2,2.2)'" -y /app/setup_recording.mp4

    # Generate Payloads
    cat << 'EOF' > /tmp/gen_payloads.py
import os
import subprocess
import hmac
import hashlib
import base64

SECRET = b"R3dT3am!2024"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"

def gen_cert(name, signer_key=None, signer_cert=None):
    key_path = f"/tmp/{name}.key"
    csr_path = f"/tmp/{name}.csr"
    cert_path = f"/tmp/{name}.pem"
    subprocess.run(["openssl", "req", "-newkey", "rsa:2048", "-nodes", "-keyout", key_path, "-out", csr_path, "-subj", f"/CN={name}"], check=True, capture_output=True)

    if signer_key and signer_cert:
        subprocess.run(["openssl", "x509", "-req", "-in", csr_path, "-CA", signer_cert, "-CAkey", signer_key, "-CAcreateserial", "-out", cert_path, "-days", "365"], check=True, capture_output=True)
    else:
        subprocess.run(["openssl", "x509", "-req", "-signkey", key_path, "-in", csr_path, "-out", cert_path, "-days", "365"], check=True, capture_output=True)

    with open(cert_path, "rb") as f:
        return f.read()

# Clean payloads
for i in range(10):
    cert = gen_cert(f"clean{i}", "/app/ca.key", "/app/ca.pem")
    b64_cert = base64.b64encode(cert).decode()
    cmd = f"whoami_{i}"
    mac = hmac.new(SECRET, cmd.encode(), hashlib.sha256).hexdigest()
    payload = f"{b64_cert}|{mac}|{cmd}"
    b64_payload = base64.b64encode(payload.encode()).decode()
    with open(f"{CLEAN_DIR}/payload_{i}.txt", "w") as f:
        f.write(b64_payload)

# Evil payloads
# 1. Bad HMAC
cert = gen_cert("evil1", "/app/ca.key", "/app/ca.pem")
b64_cert = base64.b64encode(cert).decode()
payload = f"{b64_cert}|badhmac|cmd"
with open(f"{EVIL_DIR}/payload_1.txt", "w") as f:
    f.write(base64.b64encode(payload.encode()).decode())

# 2. Self-signed cert
cert = gen_cert("evil2")
b64_cert = base64.b64encode(cert).decode()
mac = hmac.new(SECRET, b"cmd", hashlib.sha256).hexdigest()
payload = f"{b64_cert}|{mac}|cmd"
with open(f"{EVIL_DIR}/payload_2.txt", "w") as f:
    f.write(base64.b64encode(payload.encode()).decode())

# 3-10. Invalid base64/format
for i in range(3, 11):
    with open(f"{EVIL_DIR}/payload_{i}.txt", "w") as f:
        f.write("invalid_base64_!@#")
EOF
    python3 /tmp/gen_payloads.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
