#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace ltrace
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/setup.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "USAGE_ERR\n");
        return 2;
    }
    char *start = strstr(argv[1], "payload=");
    if (!start) {
        printf("MISSING\n");
        return 1;
    }
    start += 8; // length of "payload="
    uint32_t hash = 0xDEADBEEF;
    while (*start != '\0' && *start != ';') {
        hash = ((hash << 5) + hash) ^ (*start);
        start++;
    }
    printf("%08X\n", hash);
    return 0;
}
EOF
    gcc -O2 /tmp/setup.c -o /app/waf_cookie_hasher
    strip /app/waf_cookie_hasher
    rm /tmp/setup.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
