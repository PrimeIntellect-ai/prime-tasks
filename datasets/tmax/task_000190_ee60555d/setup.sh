#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        gcc \
        libc6-dev \
        binutils \
        file \
        strace \
        xxd

    pip3 install pytest

    mkdir -p /app/bin

    cat << 'EOF' > /tmp/wal_tracker.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main() {
    uint32_t volumes[256] = {0};
    uint8_t buffer[8];

    while (fread(buffer, 1, 8, stdin) == 8) {
        uint8_t op_type = buffer[0];
        uint8_t vol_id = buffer[1];
        // buffer[2] and buffer[3] are ignored (padding/reserved)
        uint32_t blocks = *(uint32_t*)(&buffer[4]);

        if (op_type == 1) {
            volumes[vol_id] += blocks;
        } else if (op_type == 2) {
            if (volumes[vol_id] < blocks) {
                volumes[vol_id] = 0;
            } else {
                volumes[vol_id] -= blocks;
            }
        } else if (op_type == 3) {
            volumes[vol_id] = blocks;
        } else {
            printf("ERR: Unknown OP %02x\n", op_type);
            return 1;
        }

        printf("VOL %d: %u\n", vol_id, volumes[vol_id]);
    }

    return 0;
}
EOF

    gcc -O2 /tmp/wal_tracker.c -o /app/bin/wal_tracker
    strip /app/bin/wal_tracker
    chmod +x /app/bin/wal_tracker
    rm /tmp/wal_tracker.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
