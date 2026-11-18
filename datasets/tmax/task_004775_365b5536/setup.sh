#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        binutils \
        strace \
        bsdmainutils

    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/fw_inspector.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[12];
    if (fread(magic, 1, 12, f) != 12) return 1;
    if (memcmp(magic, "FWPK\x01\x00\x00\x00\x00\x00\x00\x00", 12) != 0) return 1;
    unsigned int n = 0;
    if (fread(&n, 4, 1, f) != 1) return 1;
    char *meta = malloc(n + 1);
    if (fread(meta, 1, n, f) != n) return 1;
    meta[n] = '\0';
    printf("%s\n", meta);
    free(meta);
    fclose(f);
    return 0;
}
EOF

    gcc /app/fw_inspector.c -o /app/fw_inspector
    strip /app/fw_inspector

    cat << 'EOF' > /tmp/generate_corpus.py
import os
import struct
import json

def create_fw(path, magic, metadata_json, payload, override_n=None):
    meta_bytes = metadata_json.encode('utf-8')
    n = len(meta_bytes) if override_n is None else override_n
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<I', n))
        f.write(meta_bytes)
        f.write(payload)

MAGIC = b'FWPK\x01\x00\x00\x00\x00\x00\x00\x00'

for i in range(5):
    create_fw(f'/app/corpus/clean/clean_{i}.fw', MAGIC, json.dumps({"filename": f"app_{i}.bin", "version": "1.0"}), b'payload_data')

create_fw('/app/corpus/evil/evil_0.fw', MAGIC, json.dumps({"filename": "app.bin"}), b'payload', override_n=9999)
create_fw('/app/corpus/evil/evil_1.fw', MAGIC, json.dumps({"filename": "app.bin"}), b'payload', override_n=9999)
create_fw('/app/corpus/evil/evil_2.fw', MAGIC, json.dumps({"filename": "../etc/passwd"}), b'payload')
create_fw('/app/corpus/evil/evil_3.fw', MAGIC, json.dumps({"filename": "some/../../path"}), b'payload')
create_fw('/app/corpus/evil/evil_4.fw', b'BADK\x01\x00\x00\x00\x00\x00\x00\x00', json.dumps({"filename": "app.bin"}), b'payload')
EOF

    python3 /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
