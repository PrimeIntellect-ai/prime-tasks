#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev
pip3 install pytest Pillow pytesseract

cat << 'EOF' > /tmp/setup.py
import os
import json
import struct
from PIL import Image, ImageDraw, ImageFont

# 1. Generate the watermark image
os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
# Tesseract easily reads clear text
d.text((10,10), "SECURE_REPO_2024", fill=(0,0,0))
img.save('/app/watermark.png')

# 2. Setup Corpus Directories
os.makedirs('/app/corpus/clean/', exist_ok=True)
os.makedirs('/app/corpus/evil/', exist_ok=True)

def rle_encode(data: bytes) -> bytes:
    if not data: return b''
    enc = bytearray()
    i = 0
    while i < len(data):
        char = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == char and count < 255:
            count += 1
        enc.append(count)
        enc.append(char)
        i += count
    return bytes(enc)

def make_artx(magic, watermark, metadata, corrupt_rle=False, bad_size_offset=0):
    meta_bytes = metadata.encode('utf-8')
    size = len(meta_bytes) + bad_size_offset
    rle = rle_encode(meta_bytes)
    if corrupt_rle:
        rle = rle[:-1] # cut off the last byte
    return magic + watermark.encode('ascii') + struct.pack('<I', size) + rle

# Clean files
for i in range(5):
    meta = json.dumps({"artifact_id": f"clean_{i}", "data": "test"})
    payload = make_artx(b'ARTX', 'SECURE_REPO_2024', meta)
    with open(f'/app/corpus/clean/art_{i}.artx', 'wb') as f:
        f.write(payload)

# Evil files
evil_configs = [
    (b'BART', 'SECURE_REPO_2024', json.dumps({"artifact_id": "e1"}), False, 0), # bad magic
    (b'ARTX', 'HACKED_REPO_2024', json.dumps({"artifact_id": "e2"}), False, 0), # bad watermark
    (b'ARTX', 'SECURE_REPO_2024', "not_json", False, 0), # bad json
    (b'ARTX', 'SECURE_REPO_2024', json.dumps({"missing_id": "e4"}), False, 0), # missing artifact_id
    (b'ARTX', 'SECURE_REPO_2024', json.dumps({"artifact_id": "e5"}), True, 0), # bad RLE
    (b'ARTX', 'SECURE_REPO_2024', json.dumps({"artifact_id": "e6"}), False, 5), # bad size
]

for i, conf in enumerate(evil_configs):
    payload = make_artx(*conf)
    with open(f'/app/corpus/evil/evil_{i}.artx', 'wb') as f:
        f.write(payload)

os.system("chmod -R 755 /app/corpus")
os.system("chmod 644 /app/watermark.png")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
