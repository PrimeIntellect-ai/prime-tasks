#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/decode.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main() {
    uint8_t header[4];
    if (fread(header, 1, 4, stdin) != 4) return 1;
    if (memcmp(header, "ARTB", 4) != 0) return 1;

    uint32_t num_chunks;
    if (fread(&num_chunks, 4, 1, stdin) != 1) return 1;

    for (uint32_t i = 0; i < num_chunks; i++) {
        uint32_t orig_sz, comp_sz;
        if (fread(&orig_sz, 4, 1, stdin) != 1) return 1;
        if (fread(&comp_sz, 4, 1, stdin) != 1) return 1;

        uint8_t *comp_data = malloc(comp_sz);
        if (fread(comp_data, 1, comp_sz, stdin) != comp_sz) return 1;

        for (uint32_t j = 0; j < comp_sz; j += 2) {
            uint8_t count = comp_data[j];
            uint8_t val = comp_data[j+1];
            for (uint8_t k = 0; k < count; k++) {
                putchar(val);
            }
        }
        free(comp_data);
    }
    return 0;
}
EOF

    gcc -O2 -s /tmp/decode.c -o /app/decode_artb
    chmod +x /app/decode_artb
    rm /tmp/decode.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
