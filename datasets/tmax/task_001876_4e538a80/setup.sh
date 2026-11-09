#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /tmp/gen.py
import os
import struct
import base64
from PIL import Image, ImageDraw

# Generate image with spec
img = Image.new('RGB', (1200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "ASSET FORMAT SPEC V2.3: To prevent corruption, all payloads are signed with CRC-16 using polynomial 0x1021 and an XOR-out value of 0x0000. Do not reflect input or output."
d.text((10, 40), text, fill=(0, 0, 0))
img.save('/app/spec_fragment.png')

# Generate corpora
def crc16(data: bytes):
    crc = 0x0000
    for b in data:
        crc ^= (b << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ 0x1021
            else:
                crc <<= 1
            crc &= 0xFFFF
    return crc

def make_asset(payload: bytes, bad_len=False, bad_crc=False):
    crc = crc16(payload)
    if bad_crc:
        crc ^= 0xFFFF
    data_with_crc = payload + struct.pack('<H', crc)
    length = len(data_with_crc)
    if bad_len:
        length += 1
    header = struct.pack('<I', length)
    full_data = header + data_with_crc
    return base64.b64encode(full_data)

# Clean corpus
with open('/app/corpus/clean/asset1.b64', 'wb') as f:
    f.write(make_asset(b'hello world'))
with open('/app/corpus/clean/asset2.b64', 'wb') as f:
    f.write(make_asset(b'another payload'))

# Evil corpus
with open('/app/corpus/evil/evil1.b64', 'wb') as f:
    f.write(make_asset(b'hello world', bad_len=True))
with open('/app/corpus/evil/evil2.b64', 'wb') as f:
    f.write(make_asset(b'hello world', bad_crc=True))
with open('/app/corpus/evil/evil3.b64', 'wb') as f:
    f.write(b'not base64!!!')
EOF

python3 /tmp/gen.py
rm /tmp/gen.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
