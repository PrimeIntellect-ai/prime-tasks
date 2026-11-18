#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest requests flask fastapi uvicorn

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    char *hex = argv[1];
    size_t len = strlen(hex);
    for (size_t i = 0; i < len; i += 2) {
        unsigned int byte;
        sscanf(&hex[i], "%2x", &byte);
        putchar((char)(byte ^ 0x5C));
    }
    return 0;
}
EOF
    gcc -O2 -s -o /app/obfuscator_oracle /app/oracle.c
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
