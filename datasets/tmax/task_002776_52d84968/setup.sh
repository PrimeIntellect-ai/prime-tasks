#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        imagemagick \
        tesseract-ocr \
        libwebsockets-dev \
        libboost-all-dev \
        curl \
        wget

    pip3 install pytest

    mkdir -p /app

    # Create the legacy_asset_encoder
    cat << 'EOF' > /app/legacy.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint8_t header[4] = {0xDE, 0xAD, 0xBE, 0xEF};
    fwrite(header, 1, 4, stdout);
    int c;
    while ((c = fgetc(stdin)) != EOF) {
        uint8_t byte = (uint8_t)c;
        byte = byte ^ 0x42;
        byte = (byte << 3) | (byte >> 5);
        fputc(byte, stdout);
    }
    return 0;
}
EOF
    gcc -O3 /app/legacy.c -o /app/legacy_asset_encoder
    rm /app/legacy.c

    # Create the image with specs
    # Allow ImageMagick to read/write files (policy.xml fix if needed, usually ok for basic text to png)
    convert -background white -fill black -font Courier -pointsize 18 \
        label:"CONFIDENTIAL PROTOCOL V3.\nMAGIC HEADER: 0xDE 0xAD 0xBE 0xEF\nPAYLOAD ALGORITHM: For each byte in the payload after the header, apply XOR with 0x42, then bitwise rotate left (ROL) by 3 bits." \
        /app/pipeline_specs.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
