#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    mkdir -p /app
    cat << 'EOF' > /tmp/create_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "MARKER: DOC_BETA_99", fill=(0, 0, 0))
img.save('/app/diagram.png')
EOF
    python3 /tmp/create_img.py
    rm /tmp/create_img.py

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/parse_single_oracle.py
import sys
import struct

def run_oracle():
    magic = b"DOC_BETA_99"
    data = sys.stdin.buffer.read()
    idx = 0
    while True:
        idx = data.find(magic, idx)
        if idx == -1:
            break

        if idx + len(magic) + 4 > len(data):
            break

        len_bytes = data[idx + len(magic) : idx + len(magic) + 4]
        payload_len = struct.unpack("<I", len_bytes)[0]

        start_payload = idx + len(magic) + 4
        if start_payload + payload_len > len(data):
            idx += 1
            continue

        payload_bytes = data[start_payload : start_payload + payload_len]
        try:
            text = payload_bytes.decode('utf-8')
            text = text.replace("DRAFT", "FINAL").rstrip()
            print(text)
        except UnicodeDecodeError:
            pass

        idx = start_payload + payload_len

if __name__ == "__main__":
    run_oracle()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
