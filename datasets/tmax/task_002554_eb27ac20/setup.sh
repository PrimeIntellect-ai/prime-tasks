#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/uploads

    # Generate policy image
    convert -size 800x200 xc:white -pointsize 20 -fill black \
        -annotate +10+40 "CSP: default-src 'self'; script-src 'none'; object-src 'none'" \
        -annotate +10+80 "SSH: AllowUsers auditor" \
        -annotate +10+120 "PermitRootLogin no" \
        /app/policy.png

    # Create vulnerable upload handler
    cat << 'EOF' > /home/user/upload_handler.py
import sys
import base64
import os

if len(sys.argv) != 3:
    sys.exit(1)

filename_b64 = sys.argv[1]
payload_b64 = sys.argv[2]

filename = base64.b64decode(filename_b64).decode('utf-8', errors='ignore')
payload = base64.b64decode(payload_b64)

filepath = os.path.join('/home/user/uploads', filename)
with open(filepath, 'wb') as f:
    f.write(payload)
EOF

    # Create oracle handler
    cat << 'EOF' > /app/oracle_handler.py
import sys
import base64
import os

if len(sys.argv) != 3:
    sys.exit(1)

filename_b64 = sys.argv[1]
payload_b64 = sys.argv[2]

try:
    filename = base64.b64decode(filename_b64).decode('utf-8', errors='ignore')
    payload = base64.b64decode(payload_b64)
except Exception:
    sys.exit(1)

if '/' in filename or '\\' in filename or '..' in filename:
    print("CWE-22 DETECTED")
    sys.exit(1)

filepath = os.path.join('/home/user/uploads', filename)
with open(filepath, 'wb') as f:
    f.write(payload)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
