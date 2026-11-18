#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        gcc

    pip3 install pytest

    mkdir -p /app

    # Create the C program for the legacy and oracle generators
    cat << 'EOF' > /tmp/gen.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int input = atoi(argv[1]);
    int val = (input ^ 0x5A) * 3;
    printf("%d-8fA92m!Z\n", val);
    return 0;
}
EOF

    gcc -o /app/oracle_token_gen /tmp/gen.c
    cp /app/oracle_token_gen /app/legacy_token_gen
    chmod +x /app/oracle_token_gen /app/legacy_token_gen

    # Generate the key backup image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'ROTATION_SALT: 8fA92m!Z'" /app/key_backup.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
