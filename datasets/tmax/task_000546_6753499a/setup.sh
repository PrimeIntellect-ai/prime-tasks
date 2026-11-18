#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/hash.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    uint32_t sum = 0;
    uint8_t buf[4];
    size_t bytes_read;

    while ((bytes_read = fread(buf, 1, 4, f)) > 0) {
        uint32_t val = 0;
        for (size_t i = 0; i < bytes_read; i++) {
            val |= ((uint32_t)buf[i]) << (i * 8);
        }
        sum += val;
    }
    fclose(f);
    sum ^= 0xDEADBEEF;
    printf("%08x\n", sum);
    return 0;
}
EOF

gcc -O2 /app/hash.c -o /app/legacy_hash
strip /app/legacy_hash
rm /app/hash.c

mkdir -p /data/blocks

python3 -c '
import os
path = "/data/blocks"
size = 1048576

def write_file(name, byte_val):
    with open(os.path.join(path, name), "wb") as f:
        f.write(bytes([byte_val]) * size)

for i in range(4):
    write_file(f"blockA_{i}.dat", 1)

for i in range(3):
    write_file(f"blockB_{i}.dat", 2)

for i in range(3):
    write_file(f"blockC_{i}.dat", 3 + i)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /data
