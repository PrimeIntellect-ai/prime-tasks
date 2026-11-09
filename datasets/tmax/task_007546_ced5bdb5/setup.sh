#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # Create the C source code for the legacy processor
    cat << 'EOF' > processor.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        printf("Error opening file\n");
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *buf = malloc(sz);
    fread(buf, 1, sz, f);
    fclose(f);

    int sum = 0;
    for (long i = 0; i < sz - 3; i++) {
        // Magic crash trigger: 0xBA 0xAD 0xF0 0x0D
        if (buf[i] == 0xBA && buf[i+1] == 0xAD && buf[i+2] == 0xF0 && buf[i+3] == 0x0D) {
            int *p = NULL;
            *p = 42; // Intentionally segfault
        }
        sum += buf[i];
    }

    printf("SUCCESS: Processed %ld bytes, status converged.\n", sz);
    free(buf);
    return 0;
}
EOF

    # Compile it without optimizations to make decompilation straightforward but strip to hide direct source
    gcc -O0 -o data_processor processor.c
    strip data_processor
    rm processor.c

    # Create a binary payload with the poison bytes embedded
    python3 -c '
import sys
data = bytearray(b"NORMAL_DATA_START...")
data += bytearray([0x12, 0x34, 0x56, 0x78]) * 10
# Insert poison bytes
data += bytearray([0xBA, 0xAD, 0xF0, 0x0D])
data += bytearray([0x99, 0x88, 0x77, 0x66]) * 10
# Insert poison bytes again
data += bytearray([0xBA, 0xAD, 0xF0, 0x0D])
data += bytearray(b"...NORMAL_DATA_END")

with open("sensor_data.bin", "wb") as f:
    f.write(data)
'
    chmod 755 data_processor
    chmod 644 sensor_data.bin

    chmod -R 777 /home/user
