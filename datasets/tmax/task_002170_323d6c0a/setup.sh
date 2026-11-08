#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl tesseract-ocr
    pip3 install pytest pillow pytesseract cryptography

    mkdir -p /app
    mkdir -p /home/user
    mkdir -p /var/secure_keys
    chmod 777 /var/secure_keys

    # Generate the sticky note image using Python
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 0))
d = ImageDraw.Draw(img)
d.text((10, 40), 'S3cr3t_B@ckup_P@ss!', fill=(0, 0, 0))
img.save('/app/sticky_note.png')
"

    # Create the vulnerable script
    cat << 'EOF' > /tmp/deploy_keys.py
import os
import sys

if len(sys.argv) != 2:
    print("Usage: deploy_keys.py <key_file>")
    sys.exit(1)

os.system(f"cp {sys.argv[1]} /var/secure_keys/")
EOF

    # Tar and encrypt
    cd /tmp
    tar -czf ssh_backup.tar.gz deploy_keys.py
    openssl enc -aes-256-cbc -pbkdf2 -in ssh_backup.tar.gz -out /home/user/ssh_backup.enc -pass pass:'S3cr3t_B@ckup_P@ss!'

    rm /tmp/deploy_keys.py /tmp/ssh_backup.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
