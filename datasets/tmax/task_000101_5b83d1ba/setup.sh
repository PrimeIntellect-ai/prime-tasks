#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go jq
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/legacy_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    if (fread(magic, 1, 4, f) != 4) { fclose(f); return 1; }
    uint8_t count;
    if (fread(&count, 1, 1, f) != 1) { fclose(f); return 1; }

    printf("[");
    for (int i = 0; i < count; i++) {
        uint8_t len;
        if (fread(&len, 1, 1, f) != 1) break;
        char name[256] = {0};
        if (fread(name, 1, len, f) != len) break;
        uint32_t size;
        if (fread(&size, 4, 1, f) != 1) break;
        fseek(f, size, SEEK_CUR);

        printf("{\"name\": \"%s\", \"size\": %u}", name, size);
        if (i < count - 1) printf(", ");
    }
    printf("]\n");
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/legacy_parser.c -o /app/legacy_parser
    strip /app/legacy_parser

    cat << 'EOF' > /app/generate_corpus.py
import struct
import os

def write_file(path, magic, count, entries):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<B', count))
        for name, size, data in entries:
            name_bytes = name.encode('ascii')
            f.write(struct.pack('<B', len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack('<I', size))
            f.write(data)

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Clean
write_file('/app/corpus/clean/clean_1.bin', b'BKP\x01', 1, [('file1.txt', 4, b'aaaa')])
write_file('/app/corpus/clean/clean_2.bin', b'BKP\x01', 2, [('file1.txt', 4, b'aaaa'), ('file2.txt', 0, b'')])
write_file('/app/corpus/clean/clean_3.bin', b'BKP\x01', 1, [('file1.txt', 10, b'a'*10)])
write_file('/app/corpus/clean/clean_4.bin', b'BKP\x01', 1, [('file1.txt', 1, b'a')])
write_file('/app/corpus/clean/clean_5.bin', b'BKP\x01', 0, [])

# Evil
write_file('/app/corpus/evil/evil_1.bin', b'BKP\x02', 1, [('file1.txt', 4, b'aaaa')])
write_file('/app/corpus/evil/evil_2.bin', b'BKP\x01', 1, [('../etc/passwd', 4, b'aaaa')])
write_file('/app/corpus/evil/evil_3.bin', b'BKP\x01', 1, [('/root/secret', 4, b'aaaa')])
write_file('/app/corpus/evil/evil_4.bin', b'BKP\x01', 1, [('file1.txt', 99999, b'aaaa')])

with open('/app/corpus/evil/evil_5.bin', 'wb') as f:
    f.write(b'BKP\x01\x01\x05fil')
EOF

    python3 /app/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
