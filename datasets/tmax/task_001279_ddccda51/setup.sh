#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace ltrace
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/auth.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    char *input = argv[1];
    int len = strlen(input);
    for (int i = 0; i < len; i++) {
        unsigned char c = input[i];
        unsigned char res = (c ^ 0x3A) + 5;
        printf("%02x", res);
    }
    printf("\n");
    return 0;
}
EOF

    gcc /tmp/auth.c -o /app/auth_validator
    strip -s /app/auth_validator
    rm /tmp/auth.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
