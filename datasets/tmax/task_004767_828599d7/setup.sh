#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow numpy pytesseract

    mkdir -p /app/telemetry_data

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import random
from PIL import Image, ImageDraw, ImageFont

text = """TELEMETRY RECORD FORMAT (LITTLE ENDIAN):
Offset 0: TIMESTAMP (uint64) - 8 bytes
Offset 8: SENSOR_ID (uint16) - 2 bytes
Offset 10: STATUS_CODE (uint16) - 2 bytes
Offset 12: VALUE (double) - 8 bytes
Offset 20: PADDING (char array) - 12 bytes
TOTAL RECORD SIZE: 32 bytes"""

img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 18)
except:
    font = ImageFont.load_default()
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/schema.png')

timestamp = 1000000
truth_records = []
for i in range(50):
    filepath = f"/app/telemetry_data/data_{i:02d}.bin"
    with open(filepath, 'wb') as f:
        for _ in range(10000):
            timestamp += 1
            sensor_id = random.randint(1, 100)
            status_code = random.choice([200, 201, 404, 500])
            value = random.uniform(-100.0, 100.0)

            record = struct.pack('<QHHd12s', timestamp, sensor_id, status_code, value, b'\x00'*12)
            f.write(record)

            if status_code not in (404, 500):
                truth_record = struct.pack('<QHHd', timestamp, sensor_id, status_code, value)
                truth_records.append(truth_record)

with open('/tmp/ground_truth.bin', 'wb') as f:
    for tr in truth_records:
        f.write(tr)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
