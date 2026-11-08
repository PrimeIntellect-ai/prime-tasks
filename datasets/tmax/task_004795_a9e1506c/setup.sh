#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ libsqlite3-dev sqlite3 binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy_masker.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int len = strlen(argv[1]);
    for (int i = len - 1; i >= 0; i--) {
        printf("%02x", (unsigned char)(argv[1][i] ^ 0x42));
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_masker.c -o /app/legacy_masker
    strip /app/legacy_masker
    chmod +x /app/legacy_masker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
