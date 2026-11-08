#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    mkdir -p /app/bin

    cat << 'EOF' > /tmp/key_gen.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *s = argv[1];
    uint32_t h = 0x811c9dc5;
    for (int i = 0; s[i] != '\0'; i++) {
        h ^= (uint8_t)s[i];
        h = h * 0x01000193;
    }
    h ^= (strlen(s) * 42);
    printf("%u\n", h);
    return 0;
}
EOF

    gcc -O2 /tmp/key_gen.c -o /app/bin/key_gen
    strip /app/bin/key_gen
    rm /tmp/key_gen.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
