#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr openssl gcc libc6-dev
    pip3 install pytest pillow

    mkdir -p /app
    mkdir -p /home/user/certs

    cat << 'EOF' > /app/hidden_test_logs.csv
Req1,a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4,default-src 'self'; require-trusted-types-for 'script'
Req2,a1b2c3,default-src 'self'; require-trusted-types-for 'script'
Req3,a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4,default-src 'self'
Req4,11223344556677889900aabbccddeeff,require-trusted-types-for 'script'; default-src 'self'; img-src https:
EOF

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'AUTH_MASTER_8472', fill=(0, 0, 0))
img.save('/app/legacy_token.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
