#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gdb strace ltrace binutils xxd
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/obfuscator.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int main() {
    uint8_t buffer[4096];
    size_t bytes_read = fread(buffer, 1, sizeof(buffer), stdin);

    size_t i = 0;
    while (i < bytes_read) {
        uint8_t chunk[4];
        if (i + 4 <= bytes_read) {
            memcpy(chunk, buffer + i, 4);
        } else {
            size_t remaining = bytes_read - i;
            memcpy(chunk, buffer + i, remaining);
            uint8_t pad_val = (uint8_t)(bytes_read % 256);
            for (size_t j = remaining; j < 4; j++) {
                chunk[j] = pad_val;
            }
        }

        uint32_t val = chunk[0] | (chunk[1] << 8) | (chunk[2] << 16) | (chunk[3] << 24);
        val = val ^ 0xCAFEBABE;
        val = (val + 0x1337) & 0xFFFFFFFF;

        uint8_t out[4];
        out[0] = val & 0xFF;
        out[1] = (val >> 8) & 0xFF;
        out[2] = (val >> 16) & 0xFF;
        out[3] = (val >> 24) & 0xFF;

        fwrite(out, 1, 4, stdout);
        i += 4;
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/telemetry_obfuscator /app/obfuscator.c
    rm /app/obfuscator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
