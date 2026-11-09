#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        gdb \
        sleuthkit \
        e2fsprogs \
        e2tools \
        binutils

    pip3 install pytest

    mkdir -p /app

    # Create and compile oracle.c
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint8_t buffer[64];
    if (fread(buffer, 1, 64, stdin) != 64) return 1;

    uint32_t state = 0xDEADBEEF;
    for (int i = 0; i < 64; i++) {
        state = (state * 1664525) + 1013904223;
        buffer[i] ^= (state >> 24) & 0xFF;
    }

    fwrite(buffer, 1, 64, stdout);
    return 0;
}
EOF

    gcc /tmp/oracle.c -o /app/oracle.bin
    strip -s /app/oracle.bin

    # Create buggy obfuscator.c
    cat << 'EOF' > /tmp/obfuscator.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    uint8_t buffer[64];
    if (fread(buffer, 1, 64, stdin) != 64) return 1;

    uint32_t state;
    for (int i = 0; i < 64; i++) {
        if (buffer[i] == 0) exit(1);
        state = (state * 1664525) + 1013904223;
        buffer[i] ^= (state >> 24) & 0xFF;
    }

    fwrite(buffer, 1, 64, stdout);
    return 0;
}
EOF

    # Create ext4 image and simulate deleted file
    dd if=/dev/zero of=/app/evidence.img bs=1M count=10
    mkfs.ext4 -F /app/evidence.img

    # Copy obfuscator.c into the image and then remove it
    e2cp /tmp/obfuscator.c /app/evidence.img:/obfuscator.c
    e2rm /app/evidence.img:/obfuscator.c

    # Cleanup temporary files
    rm /tmp/oracle.c /tmp/obfuscator.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
