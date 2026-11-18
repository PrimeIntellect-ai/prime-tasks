#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr openssl gcc
    pip3 install pytest Pillow pytesseract cryptography pycryptodome

    mkdir -p /app/certs

    # Generate the secret key image using Python
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'APT29_SECRET_KEY_99', fill=(0,0,0))
img.save('/app/secret_key.png')
"

    # Generate 5 dummy certificates
    for i in $(seq 1 5); do
        openssl req -x509 -newkey rsa:2048 -keyout /app/certs/key$i.pem -out /app/certs/cert$i.pem -days 365 -nodes -subj "/CN=Dummy$i"
    done

    # Create oracle python script
    cat << 'EOF' > /app/.oracle.py
#!/usr/bin/env python3
import sys
print("AUTH_FAILED")
EOF
    chmod +x /app/.oracle.py

    # Create compiled oracle
    cat << 'EOF' > /app/oracle.c
#include <unistd.h>
int main(int argc, char *argv[]) {
    execv("/app/.oracle.py", argv);
    return 0;
}
EOF
    gcc /app/oracle.c -o /app/oracle_decoder
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
