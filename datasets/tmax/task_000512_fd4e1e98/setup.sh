#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gdb strace xxd binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_archiver.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint8_t buffer[4096];
    size_t bytes_read;
    while ((bytes_read = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
        fwrite("DATA", 1, 4, stdout);
        uint32_t size = (uint32_t)bytes_read;
        fwrite(&size, sizeof(uint32_t), 1, stdout);
        fwrite(buffer, 1, bytes_read, stdout);
        uint8_t checksum = 0;
        for (size_t i = 0; i < bytes_read; ++i) {
            checksum ^= buffer[i];
        }
        fwrite(&checksum, 1, 1, stdout);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_archiver.c -o /app/legacy_archiver
    strip /app/legacy_archiver
    rm /tmp/legacy_archiver.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
