#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return 1;
    if (strncmp(magic, "DARC", 4) != 0) return 1;
    uint16_t count;
    if (fread(&count, 2, 1, f) != 1) return 1;
    for (int i=0; i<count; i++) {
        uint16_t path_len;
        if (fread(&path_len, 2, 1, f) != 1) return 1;
        char path[65536] = {0};
        if (fread(path, 1, path_len, f) != path_len) return 1;
        uint32_t size;
        if (fread(&size, 4, 1, f) != 1) return 1;
        char *data = malloc(size);
        if (fread(data, 1, size, f) != size) { free(data); return 1; }
        FILE *out = fopen(path, "wb");
        if (out) {
            fwrite(data, 1, size, out);
            fclose(out);
        }
        free(data);
    }
    fclose(f);
    return 0;
}
EOF
    gcc -O2 -o /app/extractor /app/extractor.c
    strip /app/extractor
    rm /app/extractor.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/dataset/clean
    mkdir -p /home/user/dataset/evil

    cat << 'EOF' > /tmp/gen.py
import struct
import os
import random

def create_archive(path, files):
    with open(path, 'wb') as f:
        f.write(b'DARC')
        f.write(struct.pack('<H', len(files)))
        for fname, data in files:
            fname_b = fname.encode('utf-8')
            f.write(struct.pack('<H', len(fname_b)))
            f.write(fname_b)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

for i in range(50):
    files = []
    for j in range(random.randint(1, 5)):
        fname = f"log_{i}_{j}.log"
        data = b"Safe log data\n" * random.randint(1, 10)
        files.append((fname, data))
    create_archive(f'/home/user/dataset/clean/archive_{i}.darc', files)

for i in range(50):
    files = []
    for j in range(random.randint(1, 5)):
        if j == 0:
            fname = random.choice(["/etc/passwd", "../root_key", "dir/../../test", "/tmp/evil"])
        else:
            fname = f"log_{i}_{j}.log"
        data = b"Evil log data\n" * random.randint(1, 10)
        files.append((fname, data))
    create_archive(f'/home/user/dataset/evil/archive_{i}.darc', files)
EOF
    python3 /tmp/gen.py
    rm /tmp/gen.py

    chmod -R 777 /home/user
