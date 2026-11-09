#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr openssl
    pip3 install pytest pillow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/certs
    mkdir -p /home/user/app/bin
    mkdir -p /home/user/app/source
    mkdir -p /home/user/backups
    mkdir -p /app

    echo "echo 'corrupted'" > /home/user/app/bin/secure_exec

    echo "echo 'backup 1'" > /home/user/backups/backup_A.bin
    echo "echo 'correct binary v2'" > /home/user/backups/backup_B.bin
    echo "echo 'backup 3'" > /home/user/backups/backup_C.bin

    cat << 'EOF' > /home/user/app/source/main.py
def connect():
    host = "localhost"
    Password = "super_secret_password"
    return host
EOF

    cat << 'EOF' > /home/user/app/source/utils.py
def get_user():
    return "admin"
EOF

    cat << 'EOF' > /home/user/app/source/config.js
const config = {
    username: "db_admin",
    password : 'another_password123',
    host: "10.0.0.1"
};
EOF

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
import hashlib

content = b"echo 'correct binary v2'\n"
target_hash = hashlib.sha256(content).hexdigest()

text = f"""SERVER SECURITY POLICY

1. /home/user/app/config.yml must be 0600
2. /home/user/app/certs/server.key must be 0400
3. Target SHA-256 for secure_exec is:
{target_hash}
"""

img = Image.new('RGB', (800, 300), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 20), text, fill=(0, 0, 0))
img.save('/app/policy.png')
EOF
    python3 /tmp/make_image.py

    touch /home/user/app/config.yml

    chmod -R 777 /home/user
    chmod 644 /home/user/app/config.yml
    chmod 755 /home/user/app/bin/secure_exec
