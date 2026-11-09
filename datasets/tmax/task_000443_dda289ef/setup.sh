#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow pytesseract

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_data.py
import json
import random
import uuid
from PIL import Image, ImageDraw

# Generate Image
text = """WAF SECURITY POLICY v2.1
Rule 1 [Injection]: BLOCK request if the 'uri' contains the string '<script>' or 'javascript:' (case-insensitive).
Rule 2 [Certificates]: BLOCK request if 'cert_metadata' is present AND ('issuer' contains 'Untrusted' OR 'depth' is less than 2).
Rule 3 [Headers]: BLOCK request if any individual header value in 'headers' exceeds 128 characters in length.
Rule 4 [Cookies]: BLOCK request if 'set_cookie' is present but does NOT contain both 'Secure' and 'HttpOnly' attributes."""

img = Image.new('RGB', (1000, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/policy_scan.png')

# Generate Dataset
dataset = []
ground_truth = []

random.seed(42)

for _ in range(5000):
    req_id = str(uuid.uuid4())
    action = "ALLOW"

    # Rule 1
    uri = "/index.html"
    if random.random() < 0.1:
        uri += "?q=<script>alert(1)</script>"
        action = "BLOCK"
    elif random.random() < 0.1:
        uri = "JaVaScRiPt:alert(1)"
        action = "BLOCK"

    # Rule 2
    cert_metadata = None
    if random.random() < 0.5:
        issuer = "Trusted CA"
        depth = 3
        if random.random() < 0.2:
            issuer = "Untrusted Root"
            action = "BLOCK"
        if random.random() < 0.2:
            depth = 1
            action = "BLOCK"
        cert_metadata = {"issuer": issuer, "depth": depth}

    # Rule 3
    headers = {"User-Agent": "Mozilla/5.0", "Accept": "text/html"}
    if random.random() < 0.1:
        headers["X-Custom"] = "A" * 129
        action = "BLOCK"

    # Rule 4
    set_cookie = None
    if random.random() < 0.3:
        set_cookie = "session=123"
        if random.random() < 0.5:
            set_cookie += "; Secure; HttpOnly"
        else:
            if random.random() < 0.5:
                set_cookie += "; Secure"
            else:
                set_cookie += "; HttpOnly"
            action = "BLOCK"

    entry = {
        "id": req_id,
        "uri": uri,
        "headers": headers,
        "set_cookie": set_cookie,
        "cert_metadata": cert_metadata
    }

    dataset.append(entry)
    ground_truth.append({"id": req_id, "action": action})

with open('/app/traffic_dataset.jsonl', 'w') as f:
    for item in dataset:
        f.write(json.dumps(item) + '\n')

with open('/app/ground_truth.jsonl', 'w') as f:
    for item in ground_truth:
        f.write(json.dumps(item) + '\n')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
