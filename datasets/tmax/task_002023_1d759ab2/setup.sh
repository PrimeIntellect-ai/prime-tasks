#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/legacy_service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void crash_handler() {
    volatile int *ptr = NULL;
    *ptr = 0xDEADBEEF; // Deliberate segfault
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <8-char-key>\n", argv[0]);
        crash_handler();
    }

    if (strlen(argv[1]) != 8) {
        crash_handler();
    }

    char target[8] = {0x4A, 0x75, 0x76, 0x43, 0x6C, 0x7D, 0x3C, 0x3C};

    for (int i = 0; i < 8; i++) {
        if ((argv[1][i] ^ 0x05) != target[i]) {
            crash_handler();
        }
    }

    printf("Success! System initialized.\n");
    return 0;
}
EOF

    gcc -O0 -g -o /home/user/legacy_service /tmp/legacy_service.c
    rm /tmp/legacy_service.c

    chmod -R 777 /home/user
