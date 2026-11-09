#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        git \
        logrotate \
        cron \
        nginx \
        openssl \
        gcc \
        libssl-dev

    pip3 install pytest

    # Create the legacy binary
    mkdir -p /app
    cat << 'EOF' > /app/legacy.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/md5.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    char *input = argv[1];
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)input, strlen(input), digest);
    char md5_hex[33];
    for(int i = 0; i < 16; i++) {
        sprintf(&md5_hex[i*2], "%02x", (unsigned int)digest[i]);
    }

    char padded_input[9];
    strncpy(padded_input, input, 8);
    int len = strlen(input);
    for(int i = len; i < 8; i++) {
        padded_input[i] = 'X';
    }
    padded_input[8] = '\0';

    char result[17];
    for(int i = 0; i < 8; i++) {
        result[i*2] = md5_hex[i];
        result[i*2+1] = padded_input[i];
    }
    result[16] = '\0';
    printf("%s\n", result);
    return 0;
}
EOF
    gcc -Wno-deprecated-declarations -o /app/legacy_prov_hash /app/legacy.c -lssl -lcrypto
    strip /app/legacy_prov_hash
    rm /app/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
