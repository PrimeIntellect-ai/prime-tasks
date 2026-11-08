#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb ltrace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/legacy_auth.c
#include <stdio.h>
#include <string.h>

unsigned int custom_hash(const char *str) {
    unsigned int hash = 0x1337;
    while (*str) {
        hash = (hash << 5) + hash + (*str++);
        hash ^= 0xBEEF;
    }
    return hash;
}

int main(int argc, char **argv) {
    if(argc != 2) {
        return 1;
    }
    printf("0x%x\n", custom_hash(argv[1]));
    return 0;
}
EOF

    gcc -O1 /tmp/legacy_auth.c -o /home/user/legacy_auth
    strip /home/user/legacy_auth
    rm /tmp/legacy_auth.c
    chmod 755 /home/user/legacy_auth

    chmod -R 777 /home/user
