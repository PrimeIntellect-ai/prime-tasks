#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y gcc libc-dev tesseract-ocr imagemagick fonts-dejavu-core

    # Create /app directory
    mkdir -p /app

    # Generate the image with the required text
    convert -size 800x200 xc:black -font DejaVu-Sans -pointsize 36 -fill white -gravity center -annotate +0+0 "DEBUG: XOR_KEY=0x4B ADD_CONST=0x07" /app/server_audit.png

    # Create the oracle_decoder C source
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    size_t len = strlen(hex);
    if (len % 2 != 0) return 1;

    for (size_t i = 0; i < len; i += 2) {
        unsigned int byte;
        sscanf(&hex[i], "%2x", &byte);
        // Reverse encoding: subtract ADD_CONST, then XOR with XOR_KEY
        unsigned char decoded = ((byte - 0x07) & 0xFF) ^ 0x4B;
        putchar(decoded);
    }
    return 0;
}
EOF

    # Compile the oracle_decoder
    gcc /tmp/oracle.c -o /app/oracle_decoder
    chmod +x /app/oracle_decoder

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
