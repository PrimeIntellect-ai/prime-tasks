#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Write C source for legacy categorizer
    cat << 'EOF' > /tmp/cat.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    unsigned char b[16];
    if (fread(b, 1, 16, f) != 16) {
        fclose(f);
        return 1;
    }
    fclose(f);

    uint32_t magic = (b[0]<<24) | (b[1]<<16) | (b[2]<<8) | b[3];
    if (magic != 0xDEADBEEF) {
        return 1;
    }
    uint32_t xor_key = (b[4]<<24) | (b[5]<<16) | (b[6]<<8) | b[7];
    uint32_t enc_proj = (b[8]<<24) | (b[9]<<16) | (b[10]<<8) | b[11];
    uint32_t enc_time = (b[12]<<24) | (b[13]<<16) | (b[14]<<8) | b[15];

    uint32_t proj_id = enc_proj ^ xor_key;
    uint32_t timestamp = enc_time ^ xor_key;

    const char* type = "log";
    if (proj_id % 3 == 1) type = "media";
    else if (proj_id % 3 == 2) type = "document";

    printf("{\"project_id\": %u, \"file_type\": \"%s\", \"timestamp\": %u}\n", proj_id, type, timestamp);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 /tmp/cat.c -o /app/legacy_categorizer
    strip /app/legacy_categorizer
    rm /tmp/cat.c

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/legacy_data

    # Generate dummy .dat files
    python3 -c "
import struct
import os
import random

for i in range(20):
    xor_key = random.randint(0, 0xFFFFFFFF)
    proj_id = random.randint(1, 1000)
    timestamp = random.randint(1600000000, 1700000000)

    enc_proj = proj_id ^ xor_key
    enc_time = timestamp ^ xor_key

    data = struct.pack('>IIII', 0xDEADBEEF, xor_key, enc_proj, enc_time)
    data += os.urandom(random.randint(10, 100))

    with open(f'/home/user/legacy_data/data_{i}.dat', 'wb') as f:
        f.write(data)
"

    # Create organization rules
    cat << 'EOF' > /home/user/organization_rules.json
{
    "0": "logs",
    "1": "media",
    "2": "documents"
}
EOF

    # Set permissions
    chmod -R 777 /home/user
