#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        tar \
        gzip \
        fonts-dejavu-core

    pip3 install pytest Pillow Flask fastapi uvicorn requests

    mkdir -p /app
    mkdir -p /home/user/clean_docs

    # Create the image with the hidden token
    cat << 'EOF' > /tmp/create_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
except IOError:
    font = ImageFont.load_default()
d.text((10, 30), "AUTH_TOKEN: 773-ALPHA-991X", fill=(0,0,0), font=font)
img.save('/app/legacy_watermark.png')
EOF
    python3 /tmp/create_image.py

    # Create the archive files
    mkdir -p /tmp/docs
    cat << 'EOF' > /tmp/docs/server_migration.txt
Migration Log v1.0
STATUS: DRAFT
Admin user: admin
Contact SSN: 123-45-6789
End of log.
EOF

    cat << 'EOF' > /tmp/docs/database_schema.log
Schema init
STATUS: DRAFT
Backup operator SSN: 987-65-4321
EOF

    # Create the tar.gz archive
    cd /tmp/docs
    tar -czf /app/docs_archive.tar.gz server_migration.txt database_schema.log

    # Clean up temp files
    rm -rf /tmp/docs /tmp/create_image.py

    # Setup user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
    chmod -R 777 /app
