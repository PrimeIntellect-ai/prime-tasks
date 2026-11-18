#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/data_parser
    cd /home/user/data_parser

    # Create the vulnerable C program
    cat << 'EOF' > parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void parse_telemetry(const uint8_t *data, size_t size) {
    size_t i = 0;
    while (i < size) {
        if (data[i] == 0xAA) {
            // Command byte found
            if (i + 4 >= size) {
                break; // Not enough bytes for length, stop
            }
            // Read 32-bit length (little endian)
            uint32_t length = data[i+1] | (data[i+2] << 8) | (data[i+3] << 16) | (data[i+4] << 24);

            // BUG: Fails to check if i + 5 + length > size, leading to out-of-bounds read
            uint32_t checksum = 0;
            for (uint32_t j = 0; j < length; j++) {
                checksum += data[i + 5 + j]; // SEGFAULT here if length is huge
            }
            printf("Block checksum: %u\n", checksum);
            i += 5 + length;
        } else {
            i++;
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *buffer = malloc(size);
    fread(buffer, 1, size, f);
    fclose(f);

    parse_telemetry(buffer, size);
    free(buffer);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > Makefile
all:
	gcc -O0 -g parser.c -o parser
EOF

    # Compile
    gcc -O0 -g parser.c -o parser

    # Create telemetry.bin using Python to ensure exact byte values and size
    python3 -c '
import os
with open("telemetry.bin", "wb") as f:
    f.write(os.urandom(1000))
    f.write(b"\xAA\xFF\xFF\xFF\xFF")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data_parser
    chmod -R 777 /home/user
