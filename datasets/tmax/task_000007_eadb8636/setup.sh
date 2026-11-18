#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/cleaner_oracle.c
#include <stdio.h>
#include <stdint.h>
#include <math.h>

int main() {
    int32_t val;
    uint32_t nan_bits = 0x7FC00000;
    float nan_val = *((float*)&nan_bits);

    while (fread(&val, sizeof(int32_t), 1, stdin) == 1) {
        float out;
        if (val == -9999) {
            out = nan_val;
        } else {
            out = (float)val * 0.0625f;
        }
        fwrite(&out, sizeof(float), 1, stdout);
    }
    return 0;
}
EOF
    gcc -O2 -s /tmp/cleaner_oracle.c -o /app/cleaner_oracle
    rm /tmp/cleaner_oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
