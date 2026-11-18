#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr jq openssl
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /setup.py
import os
import json
import hmac
import hashlib
from PIL import Image, ImageDraw

# Generate Image
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 100), "The Q4 master rotation key is: 9f8e7d6c5b4a3f2e1d", fill=(0, 0, 0))
img.save('/app/rotation_memo.png')

KEY = b"9f8e7d6c5b4a3f2e1d"

def make_hmac(user, nonce):
    msg = f"{user}:{nonce}".encode()
    return hmac.new(KEY, msg, hashlib.sha256).hexdigest()

# Clean
for i in range(5):
    user = f"user{i}"
    nonce = f"nonce{i}"
    with open(f"/app/corpus/clean/clean{i}.json", "w") as f:
        json.dump({"user": user, "nonce": nonce, "hmac": make_hmac(user, nonce)}, f)

# Evil 1: Valid user, tampered nonce
with open("/app/corpus/evil/evil1.json", "w") as f:
    json.dump({"user": "bob", "nonce": "123", "hmac": make_hmac("bob", "124")}, f)

# Evil 2: Valid user, random hex
with open("/app/corpus/evil/evil2.json", "w") as f:
    json.dump({"user": "bob", "nonce": "123", "hmac": "deadbeef" * 8}, f)

# Evil 3: Malicious user, valid HMAC
user3 = "bob; rm -rf /"
with open("/app/corpus/evil/evil3.json", "w") as f:
    json.dump({"user": user3, "nonce": "123", "hmac": make_hmac(user3, "123")}, f)

# Evil 4: Malicious user, invalid HMAC
with open("/app/corpus/evil/evil4.json", "w") as f:
    json.dump({"user": "alice|ls", "nonce": "123", "hmac": "deadbeef" * 8}, f)

# Evil 5: Missing HMAC
with open("/app/corpus/evil/evil5.json", "w") as f:
    json.dump({"user": "bob", "nonce": "123"}, f)
EOF

    python3 /setup.py
    rm /setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
