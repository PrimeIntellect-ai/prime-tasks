#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint32_t window[4] = {0, 0, 0, 0};
    int count = 0;
    int c;
    while ((c = getchar()) != EOF) {
        uint32_t cp = 0;
        if (c <= 0x7F) {
            cp = c;
        } else if ((c & 0xE0) == 0xC0) {
            cp = c & 0x1F;
            cp = (cp << 6) | (getchar() & 0x3F);
        } else if ((c & 0xF0) == 0xE0) {
            cp = c & 0x0F;
            cp = (cp << 6) | (getchar() & 0x3F);
            cp = (cp << 6) | (getchar() & 0x3F);
        } else if ((c & 0xF8) == 0xF0) {
            cp = c & 0x07;
            cp = (cp << 6) | (getchar() & 0x3F);
            cp = (cp << 6) | (getchar() & 0x3F);
            cp = (cp << 6) | (getchar() & 0x3F);
        }
        window[0] = window[1];
        window[1] = window[2];
        window[2] = window[3];
        window[3] = cp;
        uint32_t sum = window[0] + window[1] + window[2] + window[3];
        fprintf(stdout, "W_SUM: %u\n", sum);
        count++;
        if (count % 5 == 0) {
            fprintf(stderr, "LOG: Processed %d chars\n", count);
        }
    }
    return 0;
}
EOF
    gcc -O2 /tmp/legacy.c -o /app/legacy_aggregator
    strip /app/legacy_aggregator
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
