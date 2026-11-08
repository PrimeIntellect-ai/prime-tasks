#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb ltrace file
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_hasher.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    uint32_t state[4] = {0x12345678, 0x9ABCDEF0, 0x13579BDF, 0x2468ACE0};
    char *input = argv[1];

    for (int i = 0; input[i] != '\0'; i++) {
        uint8_t c = input[i];
        state[0] = (state[0] ^ c) * 0x01000193; // FNV-1a style
        state[1] = (state[1] + c) ^ (state[0] >> 3);
        state[2] = (state[2] ^ (c << 4)) - state[1];
        state[3] = (state[3] + state[2]) ^ c;
    }

    printf("%08x%08x%08x%08x\n", state[0], state[1], state[2], state[3]);
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_hasher.c -o /app/legacy_hasher
    strip -s /app/legacy_hasher
    rm /tmp/legacy_hasher.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
