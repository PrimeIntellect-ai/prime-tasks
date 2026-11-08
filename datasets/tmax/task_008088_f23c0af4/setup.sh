#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/bin
    mkdir -p /home/user/artifacts

    # Create reproducible artifacts
    python3 -c "
import os
def make_file(name, size, fill):
    with open(f'/home/user/artifacts/{name}', 'wb') as f:
        f.write(bytes([fill] * size))

make_file('app_v1.bin', 1024, 0xAA)
make_file('app_v2.bin', 2048, 0xBB)
make_file('app_v3.bin', 512, 0xCC)
"

    # Create buggy C file
    cat << 'EOF' > /home/user/src/verifier.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

uint32_t calculate_checksum(const char* filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;

    fseek(f, 0, SEEK_END);
    long length = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *buffer = malloc(length);
    fread(buffer, 1, length, f);
    fclose(f);

    uint32_t checksum = 0x12345678;
    // BUG 1: length + 1 causes out of bounds read, corrupting checksum and crashing
    for (long i = 0; i <= length; i++) {
        checksum ^= buffer[i];
        checksum = (checksum << 1) | (checksum >> 31);
    }

    // BUG 2: double free
    free(buffer);
    free(buffer);

    return checksum;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    // Extract basename
    char* base = strrchr(argv[1], '/');
    base = base ? base + 1 : argv[1];
    printf("%s: %08x\n", base, calculate_checksum(argv[1]));
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
