#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev
    pip3 install pytest grpcio grpcio-tools protobuf

    mkdir -p /app
    cat << 'EOF' > /app/legacy_encoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <zlib.h>

uint8_t hamming_encode(uint8_t nibble) {
    uint8_t d1 = (nibble >> 3) & 1;
    uint8_t d2 = (nibble >> 2) & 1;
    uint8_t d3 = (nibble >> 1) & 1;
    uint8_t d4 = nibble & 1;
    uint8_t p1 = d1 ^ d2 ^ d4;
    uint8_t p2 = d1 ^ d3 ^ d4;
    uint8_t p3 = d2 ^ d3 ^ d4;
    return (p1 << 6) | (p2 << 5) | (d1 << 4) | (p3 << 3) | (d2 << 2) | (d3 << 1) | d4;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    const char *input = argv[1];
    size_t len = strlen(input);
    uint32_t crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const unsigned char*)input, len);

    size_t out_len = len + 4;
    uint8_t *buf = malloc(out_len);
    memcpy(buf, input, len);
    // Big endian CRC
    buf[len] = (crc >> 24) & 0xFF;
    buf[len+1] = (crc >> 16) & 0xFF;
    buf[len+2] = (crc >> 8) & 0xFF;
    buf[len+3] = crc & 0xFF;

    for (size_t i = 0; i < out_len; i++) {
        uint8_t hi = hamming_encode(buf[i] >> 4);
        uint8_t lo = hamming_encode(buf[i] & 0x0F);
        printf("%02x%02x", hi, lo);
    }
    printf("\n");
    free(buf);
    return 0;
}
EOF

    gcc -O2 -o /app/legacy_encoder /app/legacy_encoder.c -lz
    strip /app/legacy_encoder
    rm /app/legacy_encoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
