#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create the mock sensor_parser binary
    cat << 'EOF' > /tmp/sensor_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) { fclose(f); return 1; }
    if (strncmp(magic, "SENS", 4) != 0) { fclose(f); return 1; }
    uint8_t len_bytes[2];
    if (fread(len_bytes, 1, 2, f) != 2) { fclose(f); return 1; }
    uint16_t data_length = (len_bytes[0] << 8) | len_bytes[1];

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    if (sz - 6 < data_length) {
        // Trigger a segfault to simulate the described vulnerability
        char *p = NULL;
        *p = 1;
    }
    printf("Parsed %d bytes\n", data_length);
    fclose(f);
    return 0;
}
EOF

    gcc -O2 -o /app/sensor_parser /tmp/sensor_parser.c
    strip /app/sensor_parser
    rm /tmp/sensor_parser.c

    # Generate corpus files
    python3 -c '
import os
def write_file(path, data_len, actual_data):
    with open(path, "wb") as f:
        f.write(b"SENS")
        f.write(data_len.to_bytes(2, "big"))
        f.write(actual_data)

write_file("/app/corpus/clean/sample1.bin", 4, b"ABCD")
write_file("/app/corpus/clean/sample2.bin", 10, b"0123456789")
write_file("/app/corpus/clean/sample3.bin", 0, b"")

write_file("/app/corpus/evil/crash1.bin", 10, b"ABCD")
write_file("/app/corpus/evil/crash2.bin", 5, b"12")
write_file("/app/corpus/evil/crash3.bin", 65535, b"tooshort")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
