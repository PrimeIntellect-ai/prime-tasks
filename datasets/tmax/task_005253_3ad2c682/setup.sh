#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint32_t seed;
    uint32_t iterations;
    while (scanf("%u %u", &seed, &iterations) == 2) {
        uint32_t state = seed;
        int64_t total_sum = 0;
        for (uint32_t i = 1; i <= iterations; i++) {
            state = state * 1664525 + 1013904223;
            int64_t x = state % 101;
            int64_t fx = x * x * x - 2 * x * x + x;
            total_sum += fx;
        }
        printf("%lld\n", (long long)total_sum);
    }
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/oracle_mc
    strip /app/oracle_mc
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
