#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git build-essential
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /app/dump
    mkdir -p /app/legacy-port

    # Create and compile sensor_oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main() {
    char line[256];
    float scale = 1.234567f;
    float offset = 8.910111f;
    while (fgets(line, sizeof(line), stdin)) {
        uint32_t hex_val;
        if (sscanf(line, "%8X", &hex_val) == 1 || sscanf(line, "%8x", &hex_val) == 1) {
            float x;
            memcpy(&x, &hex_val, sizeof(float));
            float result = (x * scale) + offset;
            uint32_t out_hex;
            memcpy(&out_hex, &result, sizeof(float));
            printf("%08X\n", out_hex);
        }
    }
    return 0;
}
EOF
    gcc -O2 -s -o /app/bin/sensor_oracle /tmp/oracle.c
    rm /tmp/oracle.c

    # Create dummy core dump
    dd if=/dev/urandom of=/app/dump/core.oracle bs=1024 count=10
    echo "[CONFIG] SCALE_FACTOR=1.234567" >> /app/dump/core.oracle
    echo "[CONFIG] OFFSET_VAL=8.910111" >> /app/dump/core.oracle
    dd if=/dev/urandom bs=1024 count=10 >> /app/dump/core.oracle

    # Create legacy-port git repo
    cd /app/legacy-port
    git init
    git config user.email "eng@legacy.local"
    git config user.name "Legacy Eng"

    cat << 'EOF' > process.py
def process(x):
    SCALE = 0.0
    OFFSET = 0.0
    return (x * SCALE) + OFFSET
EOF
    git add process.py
    git commit -m "Implement linear calibration: y = (x * SCALE) + OFFSET"

    cat << 'EOF' > process.py
def process(x)
    # WIP
    pass
EOF
    git add process.py
    git commit -m "WIP: refactoring"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
