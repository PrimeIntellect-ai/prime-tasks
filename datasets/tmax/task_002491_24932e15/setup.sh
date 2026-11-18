#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the obfuscated auth module
    cat << 'EOF' > /app/auth_module.py
# /app/auth_module.py
def generate_token(master_key: str, challenge: int) -> str:
    # Obfuscated token generation logic
    return hex((int(master_key, 16) ^ (challenge * 1337)) % 0xFFFFFFFF)[2:]
EOF

    # Generate the admin note image with the master key
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'CONFIDENTIAL\nDO NOT SHARE\nMASTER_KEY=f4a2b9d1', fill=(0, 0, 0))
img.save('/app/admin_note.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
