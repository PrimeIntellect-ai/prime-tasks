#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    # Create a small python script to generate data_v1.bin precisely
    cat << 'EOF' > generate_v1.py
import struct

records = [
    (1, 10.5, 1620000000),
    (2, -3.14, 1620000060),
    (3, 0.0, 1620000120)
]

with open('data_v1.bin', 'wb') as f:
    for r in records:
        f.write(struct.pack('<IfQ', *r))
EOF
    python3 generate_v1.py
    rm generate_v1.py

    # Create the broken migrate.c
    cat << 'EOF' > migrate.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

// Broken struct definition with implicit padding
typedef struct {
    uint32_t id;
    uint8_t flags;
    float value;
    uint64_t timestamp;
} RecordV2;

int main(int argc, char** argv) {
    if (argc != 3) {
        printf("Usage: %s <input_v1> <output_v2>\n", argv[0]);
        return 1;
    }

    FILE* fin = fopen(argv[1], "rb");
    FILE* fout = fopen(argv[2], "wb");
    if (!fin || !fout) return 1;

    RecordV2 rec;
    // WRONG: reading v1 data directly into v2 struct causes misalignment and garbage
    while (fread(&rec, 16, 1, fin) == 1) {
        rec.flags = 0x01;
        // WRONG: writing padded struct instead of packed 17 bytes
        fwrite(&rec, sizeof(RecordV2), 1, fout);
    }

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > Makefile
migrate: migrate.c
	gcc -Wall -Wextra -O2 -o migrate migrate.c
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
