#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/log_hasher.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main() {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
            len--;
        }

        uint32_t h = 0x5A5A5A5A;
        for (size_t i = 0; i < len; i++) {
            h ^= (uint8_t)line[i];
            h = (h << 3) | (h >> 29); // Left rotate by 3
            h += 0x12345678;
        }
        printf("%08x\n", h);
    }
    return 0;
}
EOF

    gcc -O2 -o /app/log_hasher /tmp/log_hasher.c
    strip -s /app/log_hasher
    chmod +x /app/log_hasher
    rm /tmp/log_hasher.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
