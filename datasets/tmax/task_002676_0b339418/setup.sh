#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc binutils ltrace strace xxd gdb
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2 || strlen(argv[1]) != 12) {
        return 1;
    }

    unsigned char bytes[6];
    for (int i = 0; i < 6; i++) {
        sscanf(&argv[1][i*2], "%2hhx", &bytes[i]);
        bytes[i] ^= 0x42;
    }

    unsigned short uid = (bytes[0] << 8) | bytes[1];
    unsigned short gid = (bytes[2] << 8) | bytes[3];
    unsigned short mode = (bytes[4] << 8) | bytes[5];

    if (mode & 0x0002) {
        if (uid == 0) {
            printf("CRITICAL\n");
        } else {
            printf("WARNING\n");
        }
    } else if ((mode & 0x0020) && gid == 0) {
        printf("WARNING\n");
    } else {
        printf("SECURE\n");
    }

    return 0;
}
EOF

    gcc -O2 -o /app/legacy_checker /tmp/legacy.c
    strip /app/legacy_checker
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
