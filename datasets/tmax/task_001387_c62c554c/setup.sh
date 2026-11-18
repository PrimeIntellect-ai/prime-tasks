#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the specification image
    python3 -c "
from PIL import Image, ImageDraw
text = '''Format V3 Specification:
1. The file must start with a header containing the exact string 'ARTF' encoded in UTF-16LE.
2. The input data must be divided into chunks of exactly 512 bytes (the final chunk may be smaller).
3. Each chunk must be prefixed by a 2-byte unsigned little-endian integer indicating the chunk's data size.
4. Every data byte inside the chunk must be XOR-encrypted using the constant key 0x4A.'''

img = Image.new('RGB', (1000, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/spec.png')
"

    # Create the oracle archiver in C
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint8_t header[] = { 'A', 0, 'R', 0, 'T', 0, 'F', 0 };
    fwrite(header, 1, 8, stdout);
    uint8_t buf[512];
    size_t bytes_read;
    while ((bytes_read = fread(buf, 1, 512, stdin)) > 0) {
        uint16_t len = bytes_read;
        fwrite(&len, 1, 2, stdout);
        for (size_t i = 0; i < bytes_read; i++) {
            buf[i] ^= 0x4A;
        }
        fwrite(buf, 1, bytes_read, stdout);
    }
    return 0;
}
EOF

    gcc -O3 /tmp/oracle.c -o /app/oracle_archiver
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
