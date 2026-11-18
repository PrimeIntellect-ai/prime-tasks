#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl expect binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_router.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    unsigned int sum = 0;
    for (int i = 0; argv[1][i] != '\0'; i++) {
        sum += (unsigned char)argv[1][i];
    }
    int port = 8080 + (sum % 4);
    printf("%d\n", port);
    return 0;
}
EOF

    gcc -O2 -static /app/legacy_router.c -o /app/legacy_router
    strip /app/legacy_router
    upx /app/legacy_router || true
    rm /app/legacy_router.c

    useradd -m -s /bin/bash user || true
    touch /home/user/.bashrc
    chmod -R 777 /home/user
