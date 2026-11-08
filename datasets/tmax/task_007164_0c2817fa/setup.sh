#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev ltrace strace file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/sso_validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/md5.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <url> <timestamp> <token>\n", argv[0]);
        return 1;
    }

    char* url = argv[1];
    char* ts = argv[2];
    char* provided_token = argv[3];

    // Obfuscated secret to prevent simple `strings` command discovery
    char secret[30];
    secret[0] = 'X'; secret[1] = '-'; secret[2] = 'R'; secret[3] = 'e';
    secret[4] = 'd'; secret[5] = 'T'; secret[6] = 'e'; secret[7] = 'a';
    secret[8] = 'm'; secret[9] = '-'; secret[10] = 'E'; secret[11] = 'v';
    secret[12] = 'a'; secret[13] = 's'; secret[14] = 'i'; secret[15] = 'o';
    secret[16] = 'n'; secret[17] = '-'; secret[18] = 'S'; secret[19] = 'e';
    secret[20] = 'c'; secret[21] = 'r'; secret[22] = 'e'; secret[23] = 't';
    secret[24] = '\0';

    char buffer[1024];
    // This snprintf call is easily intercepted via ltrace
    snprintf(buffer, sizeof(buffer), "%s|%s|%s", url, secret, ts);

    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)buffer, strlen(buffer), digest);

    char expected_token[MD5_DIGEST_LENGTH * 2 + 1];
    for(int i = 0; i < MD5_DIGEST_LENGTH; i++) {
        sprintf(&expected_token[i*2], "%02x", digest[i]);
    }

    if (strcmp(provided_token, expected_token) == 0) {
        printf("Valid token\n");
        return 0;
    } else {
        printf("Invalid token\n");
        return 1;
    }
}
EOF

    gcc /tmp/sso_validator.c -o /home/user/sso_validator -lssl -lcrypto -O0
    chmod +x /home/user/sso_validator
    chown user:user /home/user/sso_validator

    rm /tmp/sso_validator.c

    chmod -R 777 /home/user
