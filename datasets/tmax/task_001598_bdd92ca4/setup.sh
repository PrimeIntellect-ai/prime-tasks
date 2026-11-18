#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools
    apt-get install -y gcc golang tesseract-ocr imagemagick

    # Create directories
    mkdir -p /app/c_src
    mkdir -p /app/lib
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create the vulnerable C file
    cat << 'EOF' > /app/c_src/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int process_data(const unsigned char* data, int len) {
    if (len < 4) return -1;
    int payload_len = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
    char buffer[128];
    // VULNERABILITY: No check if payload_len > 128 or if payload_len + 4 > len
    memcpy(buffer, data + 4, payload_len);
    return 0;
}
EOF

    # Create clean corpus (payload_len = 10 <= 128)
    printf "\x0A\x00\x00\x001234567890" > /app/corpus/clean/clean1.bin
    printf "\x05\x00\x00\x00hello" > /app/corpus/clean/clean2.bin

    # Create evil corpus (payload_len = 500 > 128)
    printf "\xF4\x01\x00\x00" > /app/corpus/evil/evil1.bin
    head -c 500 /dev/zero >> /app/corpus/evil/evil1.bin

    printf "\x00\x02\x00\x00" > /app/corpus/evil/evil2.bin
    head -c 512 /dev/zero >> /app/corpus/evil/evil2.bin

    # Create sample image with hidden ground truth
    convert -size 400x100 xc:white -pointsize 24 -fill black -draw "text 10,50 'INVOICE-84920-XYZ'" /app/sample.png

    # Set permissions and create user
    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
