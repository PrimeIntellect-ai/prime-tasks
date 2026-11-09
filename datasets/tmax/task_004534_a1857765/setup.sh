#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/collatz.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[256];
    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return 1;
    }

    // Naive parse for {"query": {"value": N}}
    long long n = 0;
    char *ptr = strstr(buffer, "\"value\":");
    if (ptr) {
        ptr += 8;
        n = atoll(ptr);
    }

    if (n <= 0) return 1;

    long long original_n = n;
    long long steps = 0;
    while (n > 1) {
        if (n % 2 == 0) {
            n = n / 2;
        } else {
            n = 3 * n + 1;
        }
        steps++;
    }

    printf("{\"result\": {\"initial_value\": %lld, \"steps\": %lld}}\n", original_n, steps);
    return 0;
}
EOF

    gcc -O2 /app/collatz.c -o /app/legacy_math
    strip /app/legacy_math
    chmod +x /app/legacy_math
    rm /app/collatz.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
