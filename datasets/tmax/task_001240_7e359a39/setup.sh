#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app
    mkdir -p /opt/oracle
    mkdir -p /home/user

    # Create the image with the prefix
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'Mandatory Asset Prefix: CFG_V4_', fill=(0, 0, 0))
img.save('/app/scan_policy.png')
"

    # Create the oracle binary (Python script acting as the reference implementation)
    cat << 'EOF' > /opt/oracle/reference_sanitizer
#!/usr/bin/env python3
import sys
import os

PREFIX = "CFG_V4_"
BASE = "/config_root"

for line in sys.stdin:
    line = line.strip('\r\n')
    if not line:
        continue
    parts = line.split(" ")
    if len(parts) != 3:
        continue
    seq_id, op, raw_path = parts
    if op not in ("EXTRACT", "REMOVE"):
        continue

    # Join the base directory and the raw path, then normalize
    # In Python, if raw_path is absolute, os.path.join discards BASE.
    # This correctly simulates an absolute path Zip Slip attempt escaping BASE.
    full_path = os.path.normpath(os.path.join(BASE, raw_path))

    # Check if the normalized path escapes the base directory
    if not (full_path == BASE or full_path.startswith(BASE + '/')):
        print(f"{seq_id} REJECT")
        continue

    rel_path = os.path.relpath(full_path, BASE)
    if rel_path == '.':
        continue

    dir_name, file_name = os.path.split(rel_path)
    if dir_name == '':
        final_rel = f"{PREFIX}{file_name}"
    else:
        # Ensure forward slashes for output
        dir_name = dir_name.replace('\\', '/')
        final_rel = f"{dir_name}/{PREFIX}{file_name}"

    print(f"{seq_id} ACCEPT {final_rel}")
EOF

    chmod +x /opt/oracle/reference_sanitizer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /opt/oracle
