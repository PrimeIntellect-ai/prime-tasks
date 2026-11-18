#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/loc_encoder.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    const char* input = argv[1];
    uint32_t len = strlen(input);
    fwrite(&len, sizeof(uint32_t), 1, stdout);
    fwrite(input, 1, len, stdout);

    uint32_t total_len = sizeof(uint32_t) + len;
    uint32_t remainder = total_len % 16;
    if (remainder != 0) {
        uint32_t pad_len = 16 - remainder;
        char* padding = calloc(pad_len, 1);
        fwrite(padding, 1, pad_len, stdout);
        free(padding);
    }
    return 0;
}
EOF

    gcc -O2 /app/loc_encoder.c -o /app/loc_encoder
    strip /app/loc_encoder
    chmod +x /app/loc_encoder
    rm /app/loc_encoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
