#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
pip3 install pytest Pillow cryptography

mkdir -p /app
cd /app

# 1. Create the dashboard image with the key
python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (400, 100), color=(20, 20, 20))
d = ImageDraw.Draw(img)
d.text((10, 40), "SERVER DASHBOARD\nKEY: N3tw0rkS3cur1ty2023!@#$", fill=(0, 255, 0))
img.save("/app/dashboard.png")
'

# 2. Create the malicious C program with hardcoded IPs
cat << 'EOF' > /app/malware.c
#include <stdio.h>
int main() {
    char* c2_servers[] = {
        "192.168.1.100",
        "10.42.15.99",
        "8.8.8.8",
        "10.42.200.1"
    };
    printf("Connecting to %s\n", c2_servers[1]);
    return 0;
}
EOF
gcc /app/malware.c -o /app/malware.elf

# 3. Encrypt the ELF
python3 -c '
import os
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

key_string = "N3tw0rkS3cur1ty2023!@#$"
# Pad key to 32 bytes
key = key_string.ljust(32, "X").encode("utf-8")
iv = os.urandom(16)

with open("/app/malware.elf", "rb") as f:
    data = f.read()

# PKCS7 padding
pad_len = 16 - (len(data) % 16)
data += bytes([pad_len]) * pad_len

cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
encryptor = cipher.encryptor()
ciphertext = encryptor.update(data) + encryptor.finalize()

with open("/app/payload.enc", "wb") as f:
    f.write(iv + ciphertext)
'

rm /app/malware.c /app/malware.elf

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
