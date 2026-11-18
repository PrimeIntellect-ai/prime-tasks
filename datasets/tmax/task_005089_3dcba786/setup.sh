#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        libc6-dev \
        libssl-dev \
        tesseract-ocr \
        imagemagick

    pip3 install pytest Pillow

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib
import binascii
from PIL import Image, ImageDraw, ImageFont

# 1. Create Directories
os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)
os.makedirs("/app/src", exist_ok=True)

SECRET_KEY = b"Dyn@m1cT0k3n_99!"
RESTRICTED = ["root", "admin", "/proc/", "cmdline", "/bin/sh", "bash"]

# 2. Generate Image Fixture
img = Image.new('RGB', (600, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """AUTHENTICATION DAEMON SPECIFICATION

SECRET_KEY = Dyn@m1cT0k3n_99!

SECURITY POLICY:
Drop payloads containing ANY of the following 
RESTRICTED_STRINGS:
- root
- admin
- /proc/
- cmdline
- /bin/sh
- bash
"""
d.text((20, 20), text, fill=(0, 0, 0))
img.save("/app/auth_spec.png")

# 3. Generate Clean Corpus
def make_payload(data: bytes, key: bytes, corrupt_sig=False) -> str:
    m = hashlib.sha256()
    m.update(data + key)
    sig = bytearray(m.digest())
    if corrupt_sig:
        sig[0] ^= 0xFF
    raw = bytes(sig) + data
    return binascii.hexlify(raw).decode('utf-8')

clean_data = [
    b"user=johndoe;action=login",
    b"user=alice;action=view_profile",
    b"user=bob;action=logout;time=169999",
    b"system_status=ok;load=0.5",
    b"user=guest;action=register"
]

for i in range(50):
    data = clean_data[i % len(clean_data)] + f";seq={i}".encode()
    payload = make_payload(data, SECRET_KEY)
    with open(f"/app/corpus/clean/payload_{i:02d}.txt", "w") as f:
        f.write(payload)

# 4. Generate Evil Corpus
evil_data_variants = [
    (b"user=root;action=login", False), # Valid sig, restricted word
    (b"user=admin;action=drop_tables", False), # Valid sig, restricted word
    (b"cat /proc/self/cmdline", False), # Valid sig, restricted word
    (b"user=eve;/bin/sh -c id", False), # Valid sig, restricted word
    (b"user=johndoe;action=login", True), # Invalid sig, no restricted word
    (b"user=hacker;bash -i", False), # Valid sig, restricted word
]

for i in range(50):
    data, corrupt = evil_data_variants[i % len(evil_data_variants)]
    data = data + f";seq={i}".encode()
    payload = make_payload(data, SECRET_KEY, corrupt_sig=corrupt)
    with open(f"/app/corpus/evil/payload_{i:02d}.txt", "w") as f:
        f.write(payload)

# Also add a purely malformed hex file to evil
with open("/app/corpus/evil/payload_malformed.txt", "w") as f:
    f.write("ZZZZZ NOT HEX DATA ZZZZZ")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
