#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo espeak
    pip3 install pytest

    mkdir -p /app/samples

    # Generate audio
    espeak -w /app/spec_dictation.wav "The custom compression uses a simple run-length encoding. Every pair of bytes represents a length followed by a data byte. The length byte specifies how many times the data byte is repeated. However, before decompression, every single byte in the compressed stream must be XOR-shifted by the hex value four-two (0x42) to reverse the encoding obfuscation."

    # Write and compile oracle
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
int main() {
    int len, data;
    while ((len = getchar()) != EOF) {
        len ^= 0x42;
        if ((data = getchar()) == EOF) break;
        data ^= 0x42;
        for (int i = 0; i < len; i++) {
            putchar(data);
        }
    }
    return 0;
}
EOF
    gcc -O3 -static /app/oracle.c -o /app/oracle_decompressor
    strip /app/oracle_decompressor
    rm /app/oracle.c

    # Generate samples
    cat << 'EOF' > /app/gen_samples.py
import os
import random

def compress(data):
    res = bytearray()
    i = 0
    while i < len(data):
        d = data[i]
        l = 1
        while i + l < len(data) and data[i+l] == d and l < 255:
            l += 1
        res.append(l ^ 0x42)
        res.append(d ^ 0x42)
        i += l
    return res

for i in range(1, 4):
    elf_data = os.urandom(random.randint(100, 500))
    bin_data = compress(elf_data)
    with open(f"/app/samples/blob{i}.elf", "wb") as f:
        f.write(elf_data)
    with open(f"/app/samples/blob{i}.bin", "wb") as f:
        f.write(bin_data)
EOF
    python3 /app/gen_samples.py
    rm /app/gen_samples.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
