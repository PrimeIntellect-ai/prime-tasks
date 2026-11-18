#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/lib
    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /eval/corpus/clean /eval/corpus/evil

    # Create shared library
    cat << 'EOF' > /tmp/libutils.c
void dummy_func() {}
EOF
    gcc -shared -fPIC -o /app/lib/libutils.so /tmp/libutils.c

    # Create vulnerable legacy parser
    cat << 'EOF' > /tmp/legacy_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void dummy_func();

void process_payload(FILE *f) {
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return;
    if (strncmp(magic, "TELE", 4) != 0) return;

    unsigned short payload_length;
    if (fread(&payload_length, 1, 2, f) != 2) return;

    char buffer[128];
    fread(buffer, 1, payload_length, f);

    dummy_func();
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    process_payload(f);
    fclose(f);
    return 0;
}
EOF
    gcc -fno-stack-protector -o /app/legacy_parser /tmp/legacy_parser.c -L/app/lib -lutils
    strip /app/legacy_parser

    # Generate corpora
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import struct

def make_payload(path, length):
    with open(path, 'wb') as f:
        f.write(b'TELE')
        f.write(struct.pack('<H', length))
        f.write(b'A' * length)

def create_corpus(base_dir):
    os.makedirs(f'{base_dir}/clean', exist_ok=True)
    os.makedirs(f'{base_dir}/evil', exist_ok=True)

    for i in range(10):
        make_payload(f'{base_dir}/clean/clean_{i}.bin', 50 + i*5)

    for i in range(10):
        make_payload(f'{base_dir}/evil/evil_{i}.bin', 140 + i*10)

create_corpus('/app/corpus')
create_corpus('/eval/corpus')
EOF
    python3 /tmp/gen_corpus.py

    # Clean up
    rm -f /tmp/libutils.c /tmp/legacy_parser.c /tmp/gen_corpus.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
