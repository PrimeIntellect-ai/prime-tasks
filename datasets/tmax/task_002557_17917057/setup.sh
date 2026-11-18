#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow pytesseract

    mkdir -p /app /opt/verifier

    # Create the policy image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'NOTICE: Decommissioned App ID: 0x8BADF00D. Reclaim space immediately.', fill=(0, 0, 0))
img.save('/app/policy.png')
"

    # Create oracle script
    cat << 'EOF' > /opt/verifier/oracle_compactor.py
#!/usr/bin/env python3
import sys
import struct

def main():
    target_app_id = 0x8BADF00D
    magic = sys.stdin.buffer.read(8)
    if not magic:
        return
    sys.stdout.buffer.write(magic)

    while True:
        header = sys.stdin.buffer.read(8)
        if len(header) < 8:
            break
        length, app_id = struct.unpack('<II', header)

        # Read the payload in chunks to simulate true streaming, though here we just read it
        payload = sys.stdin.buffer.read(length)

        if app_id != target_app_id:
            sys.stdout.buffer.write(header)
            sys.stdout.buffer.write(payload)

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/verifier/oracle_compactor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
