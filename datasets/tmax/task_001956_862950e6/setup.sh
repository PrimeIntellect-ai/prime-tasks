#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        tesseract-ocr \
        golang-go

    pip3 install pytest PyJWT Pillow

    mkdir -p /app/clean_tokens /app/evil_tokens

    python3 -c '
import os
import jwt
import base64
import json
from PIL import Image, ImageDraw

# Generate image
img = Image.new("RGB", (800, 100), color=(0, 0, 0))
d = ImageDraw.Draw(img)
d.text((10, 10), "DO NOT SHARE: DEBUG_SECRET_KEY=z9x8c7v6b5n4m3 is enabled for legacy endpoints.", fill=(255, 255, 255))
img.save("/app/evidence.png")

# Clean tokens
secure_key = "super_secure_unknown_key_123"
for i in range(5):
    token = jwt.encode({"user": f"user{i}", "admin": False}, secure_key, algorithm="HS256")
    with open(f"/app/clean_tokens/token_{i}.txt", "w") as f:
        f.write(token)

# Evil tokens
leaked_key = "z9x8c7v6b5n4m3"

def b64(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")

# alg=none token
header_none = {"alg": "none", "typ": "JWT"}
payload_none = {"user": "admin", "admin": True}
token_none = f"{b64(header_none)}.{b64(payload_none)}."
with open("/app/evil_tokens/evil_none.txt", "w") as f:
    f.write(token_none)

# leaked key token
payload_leaked = {"user": "../../../etc/shadow", "admin": True}
token_leaked = jwt.encode(payload_leaked, leaked_key, algorithm="HS256")
with open("/app/evil_tokens/evil_leaked.txt", "w") as f:
    f.write(token_leaked)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
