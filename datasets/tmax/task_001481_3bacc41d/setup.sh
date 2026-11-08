#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest websockets

    mkdir -p /app
    cat << 'EOF' > /tmp/emu.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_STACK 100000

long long stack[MAX_STACK];
int sp = 0;

void underflow() {
    printf("ERR\n");
    exit(0);
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char token[256];
    while (fscanf(f, "%255s", token) == 1) {
        if (token[0] == 'P') {
            long long val = atoll(token + 1);
            if (sp < MAX_STACK) stack[sp++] = val;
        } else if (token[0] == 'A' && token[1] == '\0') {
            if (sp < 2) underflow();
            long long b = stack[--sp];
            long long a = stack[--sp];
            stack[sp++] = a + b;
        } else if (token[0] == 'S' && token[1] == '\0') {
            if (sp < 2) underflow();
            long long b = stack[--sp];
            long long a = stack[--sp];
            stack[sp++] = a - b;
        } else if (token[0] == 'M' && token[1] == '\0') {
            if (sp < 2) underflow();
            long long b = stack[--sp];
            long long a = stack[--sp];
            stack[sp++] = a * b;
        } else if (token[0] == 'O' && token[1] == '\0') {
            if (sp < 1) underflow();
            printf("%lld\n", stack[--sp]);
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /tmp/emu.c -o /app/legacy_emu
    strip -s /app/legacy_emu
    chmod +x /app/legacy_emu
    rm /tmp/emu.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
