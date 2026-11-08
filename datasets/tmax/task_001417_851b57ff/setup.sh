#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the image with the delimiter text
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((50, 50), "SYSTEM ARCHITECTURE V2", fill=(0,0,0))
d.text((50, 100), "STREAMING PROTOCOL CHUNKING", fill=(0,0,0))
d.text((50, 150), "DELIMITER: F00DBB11", fill=(0,0,0))
img.save('/app/system_diagram.png')
EOF
    python3 /tmp/gen_image.py

    # Create the oracle parser
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char *data = malloc(size > 0 ? size : 1);
    if (size > 0) fread(data, 1, size, f);
    fclose(f);

    int count = 0;
    for (long i = 0; i < size; ) {
        if (i + 3 < size && data[i] == 0xF0 && data[i+1] == 0x0D && data[i+2] == 0xBB && data[i+3] == 0x11) {
            printf("[LOG_SPLIT]\n");
            count++;
            i += 4;
        } else {
            putchar(data[i]);
            i++;
        }
    }
    printf("\nEOF_CHUNKS: %d\n", count);
    free(data);
    return 0;
}
EOF
    gcc -O3 /tmp/oracle.c -o /app/oracle_parser
    chmod +x /app/oracle_parser

    # Clean up
    rm /tmp/gen_image.py /tmp/oracle.c

    # User setup
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
