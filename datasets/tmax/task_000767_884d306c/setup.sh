#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        gdb \
        strace \
        ltrace \
        binutils \
        vim-common \
        hexedit

    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/encoder.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *fin = fopen(argv[1], "rb");
    if (!fin) return 1;
    FILE *fout = fopen(argv[2], "wb");
    if (!fout) {
        fclose(fin);
        return 1;
    }

    uint32_t checksum = 0;
    size_t i = 0;
    int c;
    while ((c = fgetc(fin)) != EOF) {
        uint8_t b = (uint8_t)c;
        uint8_t e = b ^ (i % 256);
        fputc(e, fout);
        checksum = (checksum + b) & 0xFFFFFFFF;
        i++;
    }

    fputc(checksum & 0xFF, fout);
    fputc((checksum >> 8) & 0xFF, fout);
    fputc((checksum >> 16) & 0xFF, fout);
    fputc((checksum >> 24) & 0xFF, fout);

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    gcc -O2 -s /tmp/encoder.c -o /app/legacy_encoder
    rm /tmp/encoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
