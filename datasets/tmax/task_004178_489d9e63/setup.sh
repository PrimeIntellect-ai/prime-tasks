#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/legacy_indexer.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    uint8_t buf[16];
    size_t read_bytes = fread(buf, 1, 16, f);
    fclose(f);

    if (read_bytes < 16) {
        fprintf(stderr, "ERROR: FILE_TOO_SHORT\n");
        return 1;
    }

    if (buf[0] != 0x4C || buf[1] != 0x47 || buf[2] != 0x43 || buf[3] != 0x59) {
        fprintf(stderr, "ERROR: INVALID_MAGIC\n");
        return 2;
    }

    uint32_t version = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);

    char author[7];
    memcpy(author, &buf[8], 6);
    author[6] = '\0';

    uint16_t flags = (buf[14] << 8) | buf[15];

    printf("LGCY_META | V:%u | AUTH:%s | FLAGS:%u\n", version, author, flags);
    return 0;
}
EOF

gcc -O2 /app/legacy_indexer.c -o /app/legacy_indexer
strip /app/legacy_indexer
rm /app/legacy_indexer.c

mkdir -p /home/user/legacy_project

python3 -c "
import os
import random
import struct

os.makedirs('/home/user/legacy_project/subdir1', exist_ok=True)
os.makedirs('/home/user/legacy_project/subdir2', exist_ok=True)

for i in range(50):
    with open(f'/home/user/legacy_project/subdir1/valid_{i}.dat', 'wb') as f:
        version = random.randint(0, 0xFFFFFFFF)
        author = bytes([random.randint(65, 90) for _ in range(6)])
        flags = random.randint(0, 0xFFFF)
        header = b'LGCY' + struct.pack('<I', version) + author + struct.pack('>H', flags)
        f.write(header + os.urandom(random.randint(0, 100)))

for i in range(50):
    with open(f'/home/user/legacy_project/subdir2/invalid_{i}.dat', 'wb') as f:
        if random.random() < 0.5:
            f.write(os.urandom(random.randint(0, 15)))
        else:
            f.write(os.urandom(16 + random.randint(0, 100)))
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
