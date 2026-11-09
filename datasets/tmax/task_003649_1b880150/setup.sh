#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create policy.ini
    cat << 'EOF' > /home/user/policy.ini
[Policy]
Forbidden = OS_EXEC, DROP_TABLE, REVERSE_SHELL
EOF

    # Create bundle generator and generate corpora
    cat << 'EOF' > /tmp/gen_bundles.py
import struct
import os

def make_bundle(path, data_chunks, macro_string):
    with open(path, 'wb') as f:
        f.write(b'ARTF\x00\x01\x00\x00')
        for d in data_chunks:
            f.write(struct.pack('<I', len(d)))
            f.write(b'\x01')
            f.write(d)
        if macro_string:
            xor_macro = bytes([b ^ 0x5A for b in macro_string.encode('utf-8')])
            # Split macro into two chunks to simulate chunking
            mid = len(xor_macro) // 2

            f.write(struct.pack('<I', mid))
            f.write(b'\x02')
            f.write(xor_macro[:mid])

            f.write(struct.pack('<I', len(xor_macro) - mid))
            f.write(b'\x02')
            f.write(xor_macro[mid:])

make_bundle('/home/user/corpus/clean/clean1.bin', [b'header_data', b'image_data'], 'PRINT "Hello World"')
make_bundle('/home/user/corpus/clean/clean2.bin', [b'metadata'], 'CALCULATE_SUM')
make_bundle('/home/user/corpus/clean/clean3.bin', [b'empty'], '')

make_bundle('/home/user/corpus/evil/evil1.bin', [b'header_data'], 'OS_EXEC("rm -rf /")')
make_bundle('/home/user/corpus/evil/evil2.bin', [b'meta'], 'DROP_TABLE users;')
make_bundle('/home/user/corpus/evil/evil3.bin', [b'data1', b'data2'], 'INIT_REVERSE_SHELL("10.0.0.1")')
EOF
    python3 /tmp/gen_bundles.py

    # Create the legacy C binary
    cat << 'EOF' > /tmp/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <bundle>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror("fopen");
        return 1;
    }
    char magic[8];
    if (fread(magic, 1, 8, f) != 8 || memcmp(magic, "ARTF\x00\x01\x00\x00", 8) != 0) {
        fprintf(stderr, "Invalid magic\n");
        fclose(f);
        return 1;
    }

    unsigned int len;
    unsigned char type;
    while (fread(&len, 4, 1, f) == 1) {
        if (fread(&type, 1, 1, f) != 1) break;
        unsigned char *buf = malloc(len);
        if (fread(buf, 1, len, f) != len) {
            free(buf);
            break;
        }
        if (type == 0x02) {
            for (unsigned int i = 0; i < len; i++) {
                putchar(buf[i] ^ 0x5A);
            }
        }
        free(buf);
    }
    fclose(f);
    return 0;
}
EOF
    gcc -O2 /tmp/extractor.c -o /app/bin_extractor
    strip /app/bin_extractor
    chmod +x /app/bin_extractor

    # Cleanup build files
    rm /tmp/gen_bundles.py /tmp/extractor.c
    apt-get remove -y gcc
    apt-get autoremove -y

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
