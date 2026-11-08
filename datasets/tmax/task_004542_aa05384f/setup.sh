#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tlv_processor
    cd /home/user/tlv_processor

    cat << 'EOF' > Makefile
tlv_decoder: main.c
	gcc -O0 -g -o tlv_decoder main.c
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void process_tlv(const uint8_t *data, size_t size) {
    size_t i = 0;
    while (i < size) {
        if (i + 2 > size) break;
        uint8_t type = data[i];
        uint8_t length = data[i+1];

        if (i + 2 + length > size) break;

        if (type == 0x01) {
            printf("String: ");
            for (int j = 0; j < length; j++) {
                putchar(data[i + 2 + j]);
            }
            printf("\n");
            i += 2 + length;
        } else if (type == 0xFF) {
            // Padding/Metadata type
            printf("Padding/Metadata (%d bytes)\n", length);
            i += 2 + length;
        } else {
            printf("Unknown type %02X\n", type);
            i += 2 + length;
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(sz);
    fread(buf, 1, sz, f);
    fclose(f);
    process_tlv(buf, sz);
    free(buf);
    return 0;
}
EOF

    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"
    git add main.c Makefile
    git commit -m "Initial commit"
    git tag v1.0

    for i in {1..140}; do
        echo "// comment $i" >> main.c
        git commit -am "Refactor chunk $i"
    done

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void process_tlv(const uint8_t *data, size_t size) {
    size_t i = 0;
    while (i < size) {
        if (i + 2 > size) break;
        uint8_t type = data[i];
        uint8_t length = data[i+1];

        if (i + 2 + length > size) break;

        if (type == 0x01) {
            printf("String: ");
            for (int j = 0; j < length; j++) {
                putchar(data[i + 2 + j]);
            }
            printf("\n");
            i += 2 + length;
        } else if (type == 0xFF) {
            printf("Padding/Metadata (%d bytes)\n", length);
            if (length > 0) {
                i += 2 + length;
            }
            // BUG: if length == 0, i is never incremented!
        } else {
            printf("Unknown type %02X\n", type);
            i += 2 + length;
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(sz);
    fread(buf, 1, sz, f);
    fclose(f);
    process_tlv(buf, sz);
    free(buf);
    return 0;
}
EOF

    git commit -am "Optimize metadata processing"
    git rev-parse HEAD > /tmp/bad_commit_hash.txt

    for i in {142..200}; do
        echo "// comment $i" >> main.c
        git commit -am "Update docs $i"
    done

    cat << 'EOF' > /home/user/payload_gen.py
import sys
with open('/home/user/payload.bin', 'wb') as f:
    # "Hello"
    f.write(bytes([0x01, 0x05]))
    f.write(b'Hello')
    # Metadata length 0 (triggering infinite loop in bad commit)
    f.write(bytes([0xFF, 0x00]))
    # "World"
    f.write(bytes([0x01, 0x05]))
    f.write(b'World')
EOF
    python3 /home/user/payload_gen.py

    chmod -R 777 /home/user
    chmod 777 /tmp/bad_commit_hash.txt
