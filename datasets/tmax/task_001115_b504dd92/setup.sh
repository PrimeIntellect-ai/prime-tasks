#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/packet_parser/data
    cd /home/user/packet_parser

    git config --global user.email "dev@example.com"
    git config --global user.name "Previous Developer"

    git init

    # Commit 1: Initial codebase with the secret key
    cat << 'EOF' > parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// DECRYPTION_KEY="A1B2C3D4E5F67890"

void parse_tlv(const unsigned char *data, int total_len, const char *key) {
    int pos = 0;
    while (pos < total_len) {
        unsigned char type = data[pos];
        unsigned char len = data[pos + 1];

        // BUG: If len is 0, pos += len + 2 will advance by 2, but if we have a malformed off-by-one where we read past, wait.
        // Let's make an explicit infinite loop bug for len == 0
        if (len == 0 && type == 0xFF) {
            // simulated hang/leak on specific malformed chunk
            char *leak = malloc(1024);
            continue; 
        }

        if (pos + 2 + len > total_len) {
            break; // out of bounds
        }

        printf("Type: %02X, Data: ", type);
        for(int i=0; i<len; i++) {
            printf("%02X", data[pos + 2 + i] ^ key[i % 16]);
        }
        printf("\n");

        pos += 2 + len;
    }
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <file> <16-char-key>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char *buffer = malloc(fsize);
    fread(buffer, 1, fsize, f);
    fclose(f);

    parse_tlv(buffer, fsize, argv[2]);
    free(buffer);
    return 0;
}
EOF
    git add parser.c
    git commit -m "Initial commit of parser with hardcoded key"

    # Commit 2: Remove the key
    sed -i 's/\/\/ DECRYPTION_KEY="A1B2C3D4E5F67890"/\/\/ DECRYPTION_KEY removed for security/g' parser.c
    git add parser.c
    git commit -m "Security: remove hardcoded master key"

    # Create Makefile
    cat << 'EOF' > Makefile
parser: parser.c
	gcc -O0 -g -o parser parser.c
EOF
    git add Makefile
    git commit -m "Add Makefile"

    # Generate capture.bin
    python3 -c '
import sys
key = b"A1B2C3D4E5F67890"
with open("/home/user/packet_parser/data/capture.bin", "wb") as f:
    # Chunk 1
    f.write(bytes([0x01, 0x04]))
    f.write(bytes([0xDE ^ key[0], 0xAD ^ key[1], 0xBE ^ key[2], 0xEF ^ key[3]]))
    # Chunk 2 (malformed)
    f.write(bytes([0xFF, 0x00]))
    # Chunk 3
    f.write(bytes([0x02, 0x02]))
    f.write(bytes([0x11 ^ key[0], 0x22 ^ key[1]]))
'

    chown -R user:user /home/user/packet_parser
    chmod -R 777 /home/user
