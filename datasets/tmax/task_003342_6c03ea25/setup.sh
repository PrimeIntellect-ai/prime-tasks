#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang gdb binutils bsdmainutils strace
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the processor binary
    cat << 'EOF' > /tmp/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    uint32_t header[4] = {0};
    if (fread(header, 1, 16, f) != 16) {
        fclose(f);
        return 0;
    }
    fclose(f);

    if (header[0] == 0xDEADBEEF) {
        if (header[2] == (header[1] ^ 0xFFFFFFFF) && header[1] > 0x0000FFFF) {
            while(1) {} // Infinite loop
        }
    }
    return 0;
}
EOF
    gcc -O2 /tmp/processor.c -o /app/processor
    strip /app/processor
    rm /tmp/processor.c

    # Generate crash dump and corpus
    cat << 'EOF' > /tmp/generate.py
import struct
import os
import random

random.seed(42)

def write_file(path, magic, length, checksum):
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', magic, length, checksum))
        f.write(b'\x00' * 4)

for i in range(50):
    length = random.randint(0, 0xFFFF)
    checksum = length ^ 0xFFFFFFFF
    write_file(f'/app/corpus/clean/file_{i}.bin', 0xDEADBEEF, length, checksum)

for i in range(50):
    length = random.randint(0x10000, 0x7FFFFFFF)
    checksum = length ^ 0xFFFFFFFF
    write_file(f'/app/corpus/evil/file_{i}.bin', 0xDEADBEEF, length, checksum)

with open('/app/crash.dmp', 'wb') as f:
    for _ in range(10):
        f.write(os.urandom(100))
        length = 0x00010000
        checksum = length ^ 0xFFFFFFFF
        f.write(struct.pack('<III', 0xDEADBEEF, length, checksum))
        f.write(b'\x00' * 4)
EOF
    python3 /tmp/generate.py
    rm /tmp/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
