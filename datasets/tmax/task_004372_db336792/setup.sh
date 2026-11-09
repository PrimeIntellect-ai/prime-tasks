#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/packer.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <zlib.h>

int main() {
    // Read all stdin into memory
    size_t capacity = 1024;
    size_t size = 0;
    unsigned char *buffer = malloc(capacity);
    size_t bytes_read;
    while ((bytes_read = fread(buffer + size, 1, capacity - size, stdin)) > 0) {
        size += bytes_read;
        if (size == capacity) {
            capacity *= 2;
            buffer = realloc(buffer, capacity);
        }
    }

    uint32_t crc = crc32(0L, Z_NULL, 0);
    if (size > 0) {
        crc = crc32(crc, buffer, size);
    }

    unsigned long destLen = compressBound(size);
    unsigned char *dest = malloc(destLen);
    compress(dest, &destLen, buffer, size);

    uint64_t uncompressed_size = size;

    // Write format
    fwrite("PACK", 1, 4, stdout);
    fwrite(&uncompressed_size, 8, 1, stdout);
    fwrite(&crc, 4, 1, stdout);
    fwrite(dest, 1, destLen, stdout);
    fwrite("END", 1, 3, stdout);

    free(buffer);
    free(dest);
    return 0;
}
EOF

    gcc -O2 -o /app/legacy_packer /tmp/packer.c -lz
    strip /app/legacy_packer
    rm /tmp/packer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
