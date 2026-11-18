#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr build-essential python3-pil
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import os
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (400, 100), color=(0, 0, 0))
d = ImageDraw.Draw(img)
d.text((10, 10), 'Attacker console\nKEY: 0x5F3A9B2E', fill=(0, 255, 0))
img.save('/app/attacker_console.png')

# Create clean and evil binaries
binaries = ['/bin/ls', '/bin/cat', '/bin/echo', '/bin/cp', '/bin/mv']
payload = b'\xdf\xce\x6e\x17\x71\xd9\x63\x0f\x6f\xc8\x69\x7e'

for b in binaries:
    with open(b, 'rb') as f:
        data = f.read()

    # Clean corpus
    with open(f'/app/corpus/clean/{os.path.basename(b)}', 'wb') as f:
        f.write(data)

    # Evil corpus
    data_mut = bytearray(data)
    while len(data_mut) % 4 != 0:
        data_mut.append(0)
    data_mut.extend(payload)
    with open(f'/app/corpus/evil/{os.path.basename(b)}', 'wb') as f:
        f.write(data_mut)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
