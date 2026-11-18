#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc imagemagick curl fonts-dejavu-core
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /app/ecc.c
#include <stdint.h>

uint32_t compute_ecc(const char* data, int length) {
    uint32_t hash = 0x811c9dc5;
    for(int i = 0; i < length; i++) {
        hash ^= (uint8_t)data[i];
        hash *= 0x01000193;
    }
    return hash;
}
EOF

    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,35 'AUTH-77X9Q2'" /app/reference_code.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
