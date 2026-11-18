#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/intercepted.wav "The launch sequence code is seven three eight four."

    mkdir -p /home/user/c2_decoder

    cat << 'EOF' > /home/user/c2_decoder/Makefile
all:
	gcc -g -O0 -o decoder decoder.c -lm
EOF

    cat << 'EOF' > /home/user/c2_decoder/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// BUG 1 (Build failure): Missing math.h
// #include <math.h> 

// BUG 2 (Recursion error): Missing base case
int derive_key(int n) {
    /* FIX: if (n <= 0) return 1; */
    return n * derive_key(n - 1); 
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <digits>\n", argv[0]);
        return 1;
    }

    char *input = argv[1];
    int len = strlen(input);
    int buffer[10];

    // BUG 3 (Off-by-one / Boundary condition): i <= len instead of i < len
    // Causes reading null terminator into atoi math or buffer overflow
    for (int i = 0; i <= len; i++) {
        buffer[i] = input[i] - '0';
    }

    float sum = 0, sum_sq = 0;
    for (int i = 0; i < len; i++) {
        sum += buffer[i];
        sum_sq += buffer[i] * buffer[i];
    }

    float mean = sum / len;
    // BUG 4 (Numerical instability): Catastrophic cancellation when variance is near zero, 
    // potentially making it slightly negative, causing sqrt to return NaN.
    // float variance = (sum_sq / len) - (mean * mean);
    // FIX: Ensure variance >= 0 before sqrt, or use a more stable one-pass/two-pass algorithm.
    float variance = (sum_sq / len) - (mean * mean);
    float stddev = sqrt(variance);

    int derived = derive_key(5); // Should be 120 if fixed to return 1 at base case n<=0.

    printf("TOKEN-%d-%.2f\n", derived, stddev);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
