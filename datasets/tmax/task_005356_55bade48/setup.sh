#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main() {
    uint32_t N;
    if (fread(&N, sizeof(uint32_t), 1, stdin) != 1) return 0;
    for (uint32_t i = 0; i < N; i++) {
        float vec[128];
        if (fread(vec, sizeof(float), 128, stdin) != 128) break;
        float means[16];
        float min_val = 0, max_val = 0;
        for (int b = 0; b < 16; b++) {
            float sum = 0;
            for (int j = 0; j < 8; j++) sum += vec[b * 8 + j];
            means[b] = sum / 8.0f;
            if (b == 0) {
                min_val = means[b];
                max_val = means[b];
            } else {
                if (means[b] < min_val) min_val = means[b];
                if (means[b] > max_val) max_val = means[b];
            }
        }
        uint8_t out[16];
        for (int b = 0; b < 16; b++) {
            if (max_val == min_val) {
                out[b] = 0;
            } else {
                out[b] = (uint8_t)(((means[b] - min_val) / (max_val - min_val)) * 255.0f);
            }
        }
        fwrite(out, sizeof(uint8_t), 16, stdout);
    }
    return 0;
}
EOF

    gcc -O3 /app/oracle.c -o /app/dim_reducer_oracle
    strip --strip-all /app/dim_reducer_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
