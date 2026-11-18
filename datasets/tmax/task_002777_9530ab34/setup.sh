#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak
    pip3 install pytest

    mkdir -p /app/legacy_auth
    cat << 'EOF' > /app/legacy_auth/auth.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

uint64_t mix_hash(uint64_t input) {
    uint64_t state = input;
    for(int i = 0; i < 5; i++) {
        state ^= (state >> 12);
        state ^= (state << 25);
        state ^= (state >> 27);
    }
    return state;
}

void read_and_verify(const char* input_string) {
    char buffer[16];
    // Vulnerability: Stack-based Buffer Overflow
    strcpy(buffer, input_string);

    uint64_t parsed_val = 0;
    sscanf(buffer, "%lu", &parsed_val);

    if (mix_hash(parsed_val) == 0x1337BEEFCAFE0000) {
        printf("Access Granted.\n");
    } else {
        printf("Access Denied.\n");
    }
}
EOF

    espeak -w /app/intercept_73.wav "seven two nine four"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
