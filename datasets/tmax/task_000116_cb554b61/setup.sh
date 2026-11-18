#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        rustc \
        cargo \
        openssl \
        && rm -rf /var/lib/apt/lists/*

    pip3 install pytest Pillow

    mkdir -p /app

    # Create the certificate
    openssl req -x509 -newkey rsa:2048 -keyout /app/server.key -out /app/server.crt -days 365 -nodes -subj "/CN=auth.corp.internal"

    # Python script to generate files
    cat << 'EOF' > /tmp/setup.py
import os
import hashlib
from PIL import Image, ImageDraw

# Create image
text = """INCIDENT RESPONSE REDACTION RULES:
1. Credit Cards: Replace all 16-digit credit card numbers (format: 4 blocks of 4 digits separated by dashes, e.g., 1234-5678-9012-3456) with ****-****-****-XXXX where XXXX is the last 4 digits.
2. SSNs: Replace all Social Security Numbers (format: XXX-XX-XXXX) with ***-**-XXXX where XXXX is the last 4 digits."""

img = Image.new('RGB', (1000, 300), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/evidence_photo.png')

# Create logs
raw_logs = []
expected_logs = ["Server CN: auth.corp.internal"]

for i in range(100):
    if i % 2 == 0:
        raw_logs.append(f"User login attempt with CC 1234-5678-9012-{i:04d} from IP 192.168.1.1")
        expected_logs.append(f"User login attempt with CC ****-****-****-{i:04d} from IP 192.168.1.1")
    else:
        raw_logs.append(f"User profile update for SSN 123-45-{i:04d} successful")
        expected_logs.append(f"User profile update for SSN ***-**-{i:04d} successful")

with open('/app/raw_logs.txt', 'w') as f:
    f.write('\n'.join(raw_logs) + '\n')

with open('/app/hidden_expected_logs.txt', 'w') as f:
    f.write('\n'.join(expected_logs) + '\n')

# SHA256
with open('/app/raw_logs.txt', 'rb') as f:
    h = hashlib.sha256(f.read()).hexdigest()

with open('/app/raw_logs.txt.sha256', 'w') as f:
    f.write(h + '  /app/raw_logs.txt\n')
EOF

    python3 /tmp/setup.py

    # Verifier script
    cat << 'EOF' > /verifier.py
import sys

def evaluate():
    try:
        with open("/app/hidden_expected_logs.txt", "r") as f:
            expected = f.read().splitlines()
        with open("/home/user/redacted_logs.txt", "r") as f:
            actual = f.read().splitlines()
    except FileNotFoundError:
        print("0.0")
        return

    if not expected or not actual:
        print("0.0")
        return

    correct = 0
    for i in range(min(len(expected), len(actual))):
        if expected[i] == actual[i]:
            correct += 1

    accuracy = correct / len(expected)
    print(f"{accuracy:.4f}")

if __name__ == "__main__":
    evaluate()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
