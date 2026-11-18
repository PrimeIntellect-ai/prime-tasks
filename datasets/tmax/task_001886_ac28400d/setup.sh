#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils gdb strace xxd
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/corpus/clean

    cat << 'EOF' > /tmp/c2_encoder.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input> <output>\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "rb");
    if (!fin) return 1;
    FILE *fout = fopen(argv[2], "wb");
    if (!fout) {
        fclose(fin);
        return 1;
    }

    uint32_t checksum = 0;
    int c;
    while ((c = fgetc(fin)) != EOF) {
        checksum += c;
        uint8_t enc = ((c ^ 0x3F) + 0x12) & 0xFF;
        fputc(enc, fout);
    }

    fputc(checksum & 0xFF, fout);
    fputc((checksum >> 8) & 0xFF, fout);
    fputc((checksum >> 16) & 0xFF, fout);
    fputc((checksum >> 24) & 0xFF, fout);

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    gcc -O2 -static -s /tmp/c2_encoder.c -o /app/c2_encoder
    rm /tmp/c2_encoder.c

    cat << 'EOF' > /tmp/generate_corpora.py
import os
import random
import struct

os.makedirs('/home/user/corpus/evil', exist_ok=True)
os.makedirs('/home/user/corpus/clean', exist_ok=True)

def encode(data):
    checksum = sum(data) & 0xFFFFFFFF
    encoded = bytearray([((b ^ 0x3F) + 0x12) & 0xFF for b in data])
    encoded += struct.pack('<I', checksum)
    return encoded

random.seed(42)

for i in range(50):
    length = random.randint(10, 1000)
    data = bytearray(random.getrandbits(8) for _ in range(length))

    with open(f'/home/user/corpus/evil/file_{i}.bin', 'wb') as f:
        f.write(encode(data))

    with open(f'/home/user/corpus/clean/file_{i}.bin', 'wb') as f:
        f.write(bytearray(random.getrandbits(8) for _ in range(length + 4)))
EOF

    python3 /tmp/generate_corpora.py
    rm /tmp/generate_corpora.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
