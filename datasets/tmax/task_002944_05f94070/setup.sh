#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        gcc g++ gdb binutils e2fsprogs extundelete
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # 1. Create legacy_parser
    cat << 'EOF' > /tmp/parser.c
#include <stdio.h>
#include <stdlib.h>

void parse(FILE *f) {
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return;
    unsigned short L;
    if (fread(&L, 2, 1, f) != 1) return;
    char *buffer = malloc(65536);
    if (!buffer) return;
    int read_bytes = fread(buffer, 1, L, f);
    if (L > 64 && read_bytes > 64 && (unsigned char)buffer[64] == 0xFF) {
        *(volatile int*)0 = 0; // Crash
    }
    free(buffer);
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    parse(f);
    fclose(f);
    return 0;
}
EOF
    gcc -O2 /tmp/parser.c -o /app/legacy_parser
    strip /app/legacy_parser

    # 2. Generate recovered_workspace.img
    mkdir -p /tmp/img_content
    cat << 'EOF' > /tmp/img_content/format_spec.txt
Format Spec:
Magic: 4 bytes "DATA" (0x44 0x41 0x54 0x41)
Length: 2 bytes unsigned integer (little endian)
Payload: Variable length, exactly 'Length' bytes long.
EOF
    cat << 'EOF' > /tmp/img_content/detector.cpp
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <file_path>\n";
        return 1;
    }
    // TODO: Implement detector logic
    return 0;
}
EOF
    dd if=/dev/zero of=/app/recovered_workspace.img bs=1M count=10
    mkfs.ext4 -d /tmp/img_content -F /app/recovered_workspace.img
    debugfs -w -R "rm format_spec.txt" /app/recovered_workspace.img
    debugfs -w -R "rm detector.cpp" /app/recovered_workspace.img

    # 3. Generate Corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import struct

def write_file(path, magic, L, payload):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<H', L))
        f.write(payload)

# Clean files
write_file('/app/corpus/clean/c1.bin', b'DATA', 10, b'A'*10)
write_file('/app/corpus/clean/c2.bin', b'DATA', 64, b'B'*64)
write_file('/app/corpus/clean/c3.bin', b'DATA', 70, b'C'*64 + b'\xFE' + b'C'*5)

# Evil files
write_file('/app/corpus/evil/e1.bin', b'DATA', 70, b'D'*64 + b'\xFF' + b'D'*5)
write_file('/app/corpus/evil/e2.bin', b'DATA', 100, b'E'*64 + b'\xFF' + b'E'*35)
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
