#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr rustc cargo unzip zip
    pip3 install pytest pillow

    mkdir -p /app

    # Create setup script to generate files without using forbidden build variables
    cat << 'EOF' > /tmp/setup.py
import zipfile
from PIL import Image, ImageDraw

# Create image
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SYSTEM SCHEMA RECOVERY\nMASTER_TOKEN: X9F2B-88ZZ1\nSERVICE_PORT: 9095"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/legacy_schema.png')

# Create zip archive
with zipfile.ZipFile('/app/backup_configs.zip', 'w') as z:
    # Use string concatenation to avoid Apptainer build variable syntax
    placeholder = '{' + '{TOKEN_PLACEHOLDER}' + '}'
    z.writestr('router_A.conf.bak', '{"device": "router_A", "auth": "' + placeholder + '"}')
    z.writestr('switch_B.conf.bak', '{"device": "switch_B", "auth": "' + placeholder + '"}')
    z.writestr('corrupted.conf.bak', '{"device": "corrupted", "auth": "bad_data_here"}')

# Corrupt the CRC of corrupted.conf.bak
with open('/app/backup_configs.zip', 'r+b') as f:
    data = f.read()
    # Find the local file header for corrupted.conf.bak
    idx = data.find(b'corrupted.conf.bak')
    if idx != -1:
        # Overwrite some bytes in the file data to cause a CRC error
        f.seek(idx + len(b'corrupted.conf.bak'))
        f.write(b'CORRUPTED_BYTES')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
