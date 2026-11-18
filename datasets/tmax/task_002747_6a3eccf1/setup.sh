#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Generate SAR files
cat << 'EOF' > /tmp/gen_sar.py
import struct
import os

def write_sar(path, entries):
    with open(path, 'wb') as f:
        f.write(b'SAR\x00')
        f.write(struct.pack('<H', len(entries)))
        for name, content in entries:
            name_bytes = name.encode('ascii')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack('<I', len(content)))
            f.write(content)

for i in range(50):
    write_sar(f'/app/corpus/clean/clean_{i}.sar', [
        (f'docs/readme_{i}.txt', b'hello'),
        (f'image_{i}.png', b'image')
    ])

for i in range(50):
    evil_paths = [
        f'../../../etc/shadow_{i}',
        f'/root/.ssh/authorized_keys_{i}',
        f'valid_dir/../../malicious_{i}.sh'
    ]
    write_sar(f'/app/corpus/evil/evil_{i}.sar', [
        ('normal.txt', b'normal'),
        (evil_paths[i % len(evil_paths)], b'evil')
    ])
EOF
python3 /tmp/gen_sar.py

# Create sarextract binary
cat << 'EOF' > /tmp/sarextract.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return 1;
    if (memcmp(magic, "SAR\0", 4) != 0) return 1;
    uint16_t num_files;
    if (fread(&num_files, 2, 1, f) != 1) return 1;
    for (int i = 0; i < num_files; i++) {
        uint16_t path_len;
        if (fread(&path_len, 2, 1, f) != 1) return 1;
        char *path = malloc(path_len + 1);
        if (fread(path, 1, path_len, f) != path_len) return 1;
        path[path_len] = 0;
        uint32_t file_size;
        if (fread(&file_size, 4, 1, f) != 1) return 1;
        char *content = malloc(file_size);
        if (fread(content, 1, file_size, f) != file_size) return 1;

        // Dummy extraction logic
        FILE *out = fopen(path, "wb");
        if (out) {
            fwrite(content, 1, file_size, out);
            fclose(out);
        }

        free(path);
        free(content);
    }
    fclose(f);
    return 0;
}
EOF

gcc /tmp/sarextract.c -o /app/sarextract
strip -s /app/sarextract

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
