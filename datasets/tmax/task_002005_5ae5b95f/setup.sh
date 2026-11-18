#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/md5.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 1;
    }
    char *input = argv[1];
    char *salt = "_legacy_mount_v2";
    size_t len = strlen(input) + strlen(salt);
    char *concat = malloc(len + 1);
    strcpy(concat, input);
    strcat(concat, salt);

    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)concat, len, digest);

    for(int i = 0; i < MD5_DIGEST_LENGTH; i++) {
        printf("%02x", digest[i]);
    }
    printf("\n");
    free(concat);
    return 0;
}
EOF

    gcc -O2 -s -o /app/legacy_hasher /tmp/hasher.c -lcrypto
    rm /tmp/hasher.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
