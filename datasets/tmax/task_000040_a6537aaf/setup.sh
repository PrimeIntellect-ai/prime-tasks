#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gdb gcc
pip3 install pytest Pillow

mkdir -p /app

# Create the vulnerable C binary
cat << 'EOF' > /app/suspicious_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char header[18];
    memset(header, 0, 18);
    fread(header, 1, 17, f);

    if (strncmp(header, "Z3R0_D4Y_P4YL04D\n", 17) != 0) {
        printf("INVALID HEADER\n");
        fclose(f);
        return 1;
    }

    char buf[64]; // Vulnerable buffer
    int i = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        buf[i++] = c ^ 0x42;
    }

    fwrite(buf, 1, i, stdout);
    fclose(f);
    return 0;
}
EOF

gcc /app/suspicious_parser.c -o /app/suspicious_parser.bin
strip /app/suspicious_parser.bin
rm /app/suspicious_parser.c

# Create the oracle script
cat << 'EOF' > /app/oracle_safe_parser.py
import sys
import os

if len(sys.argv) != 2:
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

magic = b"Z3R0_D4Y_P4YL04D\n"
if not data.startswith(magic):
    print("INVALID HEADER")
    sys.exit(1)

payload = data[len(magic):]
decoded = bytes([b ^ 0x42 for b in payload])
sys.stdout.buffer.write(decoded)
EOF

# Create the image with the magic header
cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "Z3R0_D4Y_P4YL04D", fill=(0, 0, 0))
img.save('/app/intercepted_note.png')
EOF
python3 /tmp/gen_img.py
rm /tmp/gen_img.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 755 /app
