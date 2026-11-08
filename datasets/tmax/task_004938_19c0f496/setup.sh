#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow numpy

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Setup files via Python
    python3 -c "
import os
import zipfile
from PIL import Image, ImageDraw

# 1. Generate obfuscation_key.png
img = Image.new('RGB', (200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'KEY=185', fill=(0, 0, 0))
img.save('/app/obfuscation_key.png')

# 2. Create valid JPEG images
img1 = Image.new('RGB', (100, 100), color=(255, 0, 0))
img1.save('/tmp/apple.jpg', format='JPEG')
img1.save('/app/.hidden_ref.jpg', format='JPEG')

img2 = Image.new('RGB', (100, 100), color=(0, 255, 0))
img2.save('/tmp/banana.jpg', format='JPEG')

# 3. Read bytes, XOR with 185
with open('/tmp/apple.jpg', 'rb') as f:
    apple_data = bytearray(f.read())
with open('/tmp/banana.jpg', 'rb') as f:
    banana_data = bytearray(f.read())

for i in range(len(apple_data)):
    apple_data[i] ^= 185
for i in range(len(banana_data)):
    banana_data[i] ^= 185

with open('/tmp/apple_xor.jpg', 'wb') as f:
    f.write(apple_data)
with open('/tmp/banana_xor.jpg', 'wb') as f:
    f.write(banana_data)

# 4. Create ZIP with Zip Slip
with open('/home/user/important_notes.txt', 'w') as f:
    f.write('These are my important notes.')

with zipfile.ZipFile('/app/raw_dataset.zip', 'w') as z:
    z.write('/tmp/apple_xor.jpg', arcname='apple.jpg')
    z.write('/tmp/banana_xor.jpg', arcname='banana.jpg')
    z.writestr('../../home/user/important_notes.txt', b'You have been hacked!')
"

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
