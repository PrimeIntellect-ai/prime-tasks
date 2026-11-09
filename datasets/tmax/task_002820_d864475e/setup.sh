#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/chunk_reader.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    uint32_t num_records, index_offset, data_offset;

    if (fread(magic, 1, 4, f) != 4) return 1;
    if (fread(&num_records, 4, 1, f) != 1) return 1;
    if (fread(&index_offset, 4, 1, f) != 1) return 1;
    if (fread(&data_offset, 4, 1, f) != 1) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);

    if (index_offset + num_records * 4 > size) {
        int *p = NULL;
        *p = 0;
    }

    fclose(f);
    return 0;
}
EOF

gcc /tmp/chunk_reader.c -o /app/chunk_reader
strip /app/chunk_reader

cat << 'EOF' > /tmp/generate_data.py
import struct
import os
import random

def make_file(path, is_evil):
    magic = b"CHNK"
    num_records = random.randint(10, 100)
    index_offset = 16
    data_offset = index_offset + num_records * 4

    if is_evil:
        file_size = index_offset + num_records * 4 - random.randint(1, 10)
    else:
        file_size = data_offset + random.randint(10, 100)

    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", num_records))
        f.write(struct.pack("<I", index_offset))
        f.write(struct.pack("<I", data_offset))

        if file_size > 16:
            f.write(b"\x00" * (file_size - 16))

os.makedirs("/home/user/samples/clean", exist_ok=True)
os.makedirs("/home/user/samples/evil", exist_ok=True)
os.makedirs("/validation/clean", exist_ok=True)
os.makedirs("/validation/evil", exist_ok=True)

for i in range(5):
    make_file(f"/home/user/samples/clean/file_{i}.bin", False)
    make_file(f"/home/user/samples/evil/file_{i}.bin", True)

for i in range(50):
    make_file(f"/validation/clean/file_{i}.bin", False)
    make_file(f"/validation/evil/file_{i}.bin", True)
EOF

python3 /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /validation
