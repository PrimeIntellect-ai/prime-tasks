#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace ltrace
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    uint8_t state[16] = { 'S', 'E', 'C', '_', 'R', 'O', 'T', '_', '2', '0', '2', '4', '_', '!', '@', '#' };
    char *S = argv[1];
    size_t L = strlen(S);

    for (size_t i = 0; i < L; i++) {
        state[i % 16] = (state[i % 16] + S[i]) ^ (i & 0xFF);
    }

    for (int i = 0; i < 16; i++) {
        printf("%02x", state[i]);
    }
    printf("\n");
    return 0;
}
EOF

    gcc /tmp/oracle.c -o /app/legacy_rotator
    strip -s /app/legacy_rotator
    chmod +x /app/legacy_rotator
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
