#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional packages
    apt-get install -y gcc apache2-utils

    # Create /app directory
    mkdir -p /app

    # Create and compile legacy_router
    cat << 'EOF' > /tmp/legacy_router.c
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

int main() {
    uint32_t input[2];
    if (fread(input, sizeof(uint32_t), 2, stdin) == 2) {
        uint32_t source = input[0];
        uint32_t dest = input[1];
        // Arbitrary proprietary algorithm
        uint32_t next_hop = (source ^ dest) + (source * 31) - (dest * 7);
        fwrite(&next_hop, sizeof(uint32_t), 1, stdout);
        fflush(stdout);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_router.c -o /app/legacy_router
    strip /app/legacy_router
    chmod +x /app/legacy_router
    rm /tmp/legacy_router.c

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
