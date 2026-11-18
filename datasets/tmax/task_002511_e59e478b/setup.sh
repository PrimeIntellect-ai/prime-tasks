#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils ltrace strace gdb
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_signer.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: legacy_signer <payload_id>\n");
        return 1;
    }

    char *s = argv[1];
    int len = strlen(s);

    if (len < 8 || len > 32) {
        printf("Error: Invalid length\n");
        return 1;
    }

    for (int i = 0; i < len; i++) {
        if (!isalnum((unsigned char)s[i])) {
            printf("Error: Invalid characters\n");
            return 1;
        }
    }

    for (int i = 0; i < len; i++) {
        int val = (s[i] ^ 0x2A) + (i % 3);
        printf("%02X", val & 0xFF);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_signer.c -o /app/legacy_signer
    strip /app/legacy_signer
    rm /tmp/legacy_signer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
