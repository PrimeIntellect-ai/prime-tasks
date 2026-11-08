#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_auth.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <user> <pass>\n", argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "sysadmin") == 0 && strcmp(argv[2], "legacy_p4ss") == 0) {
        printf("AUTH_SUCCESS\n");
        return 0;
    }
    printf("AUTH_FAIL\n");
    return 1;
}
EOF

    gcc -O2 -s /app/legacy_auth.c -o /app/legacy_auth
    chmod +x /app/legacy_auth
    rm /app/legacy_auth.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
