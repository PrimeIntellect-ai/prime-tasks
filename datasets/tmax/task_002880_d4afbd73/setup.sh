#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils systemd dbus
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/netdiag.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 0;
    char *input = argv[1];
    int len = strlen(input);
    for (int i = len - 1; i >= 0; i--) {
        printf("%02x", (unsigned char)(input[i] ^ 0x2A));
    }
    printf("\n");
    return 0;
}
EOF
    gcc -o /app/netdiag_obfuscated /app/netdiag.c
    strip -s /app/netdiag_obfuscated
    rm /app/netdiag.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
