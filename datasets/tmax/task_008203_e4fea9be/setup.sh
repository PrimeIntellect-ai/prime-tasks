#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /home/user/nightly
    cd /home/user/nightly

    cat << 'EOF' > inputs.txt
2.5000
1.1000
0.0001
5.4000
EOF

    cat << 'EOF' > process.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <value>\n", argv[0]);
        return 1;
    }

    float x = atof(argv[1]);

    // Calculate 1 / (sqrt(x^2 + 1) - 1)
    // For very small x, x^2 + 1 evaluates to exactly 1.0f in 32-bit float,
    // leading to sqrtf(1.0f) - 1.0f = 0.0f, and a division by zero crash (SIGFPE).
    float denominator = sqrtf(x * x + 1.0f) - 1.0f;
    float result = 1.0f / denominator;

    // Simulate crash on division by zero (some systems print Inf instead of SIGFPE for floats, 
    // so we force a crash if denominator is 0 to ensure the behavior matches the description)
    if (denominator == 0.0f) {
        int *p = NULL;
        *p = 0; // Force segfault/core dump
    }

    printf("%.2f\n", result);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
