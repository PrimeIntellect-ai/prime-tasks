#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_processor.c
#include <stdio.h>
#include <stdint.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    float sum = 0.0f;
    int counter = 0;
    uint32_t chunk;

    while (fread(&chunk, 4, 1, f) == 1) {
        if (chunk == 0xFFFFFFFF) {
            counter++;
            if (counter == 3) {
                sum = 0.0f;
                counter = 0;
            }
        } else {
            float val = *((float*)&chunk);
            if (isnan(val) || isinf(val)) {
                continue;
            } else {
                sum += val;
            }
        }
    }
    fclose(f);

    float result = sum * sum;
    printf("%.6f\n", result);
    return 0;
}
EOF

    gcc -O0 -o /app/legacy_processor /tmp/legacy_processor.c -lm
    strip /app/legacy_processor
    rm /tmp/legacy_processor.c

    mkdir -p /var/log
    cat << 'EOF' > /var/log/processor_crash.log
FATAL: System panic in module legacy_processor
Stack trace:
#0 0x00005555555551a9 in process_chunk ()
#1 0x00005555555552b4 in main ()
Hex dump of failing input sequence triggering state reset:
FF FF FF FF FF FF FF FF FF FF FF FF
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
