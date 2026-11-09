#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/traffic_dumps
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /tmp/setup.py
import json
import base64
import os
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (800, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "WARNING: High severity exfiltration detected via custom HTTP header: X-Diagnostic-Dump. Payload type: base64-encoded ELF binary.", fill=(0,0,0))
img.save('/app/alert_screenshot.png')

# Generate evil corpus
elf_payload = b'\x7fELF\x02\x01\x01\x00' + b'\x00'*10
elf_b64 = base64.b64encode(elf_payload).decode('utf-8')

for i in range(50):
    evil_req = {
        "method": "POST",
        "url": "/api/v1/status",
        "headers": {
            "Host": "example.com",
            "X-Diagnostic-Dump": elf_b64
        },
        "body": ""
    }
    with open(f'/app/corpora/evil/req_{i}.json', 'w') as f:
        json.dump(evil_req, f)

# Generate clean corpus
benign_b64 = base64.b64encode(b'Just some benign text').decode('utf-8')

for i in range(50):
    if i % 2 == 0:
        clean_req = {
            "method": "GET",
            "url": "/api/v1/health",
            "headers": {
                "Host": "example.com"
            },
            "body": ""
        }
    else:
        clean_req = {
            "method": "POST",
            "url": "/api/v1/status",
            "headers": {
                "Host": "example.com",
                "X-Diagnostic-Dump": benign_b64
            },
            "body": ""
        }
    with open(f'/app/corpora/clean/req_{i}.json', 'w') as f:
        json.dump(clean_req, f)

# Put some samples in traffic_dumps
with open('/app/traffic_dumps/sample_clean.json', 'w') as f:
    json.dump(clean_req, f)
with open('/app/traffic_dumps/sample_evil.json', 'w') as f:
    json.dump(evil_req, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
