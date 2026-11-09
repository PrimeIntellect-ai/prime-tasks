#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev socat binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/c2_auth.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/md5.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "C2_SALT_%s", argv[1]);

    unsigned char result[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)buffer, strlen(buffer), result);

    for(int i = 0; i < MD5_DIGEST_LENGTH; i++) {
        printf("%02x", result[i]);
    }
    printf("\n");
    return 0;
}
EOF
    gcc -O2 /tmp/c2_auth.c -o /app/c2_auth -lcrypto
    strip /app/c2_auth
    rm /tmp/c2_auth.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
