#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential libssl-dev tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the C program for the rogue auth binary
    cat << 'EOF' > /tmp/rogue_auth.c
#include <stdio.h>
#include <string.h>
#include <openssl/sha.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    char *username = argv[1];
    char *origin = argv[2];
    char *salt = "hX9$mK2p";
    char buffer[2048];
    snprintf(buffer, sizeof(buffer), "%s|%s|%s", origin, username, salt);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)buffer, strlen(buffer), hash);

    printf("tk_");
    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        printf("%02x", hash[i]);
    }
    return 0;
}
EOF

    gcc /tmp/rogue_auth.c -o /app/rogue_auth.elf -lssl -lcrypto
    chmod +x /app/rogue_auth.elf

    # Create the ransom note image using Python and Pillow
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
# Use default font if no specific font is loaded
d.text((50, 100), "SYSTEM COMPROMISED. SALT: hX9$mK2p", fill=(0, 0, 0))
img.save('/app/ransom_note.png')
EOF
    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
