#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ libssl-dev
    pip3 install pytest

    # Create the legacy_token_validator binary
    mkdir -p /app
    cat << 'EOF' > /app/validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/hmac.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 2;
    char msg[512];
    snprintf(msg, sizeof(msg), "%s%s", argv[1], argv[2]);
    const char *key = "IoT_Sec_Key_99!";
    unsigned int len = 0;
    unsigned char *result = HMAC(EVP_sha256(), key, strlen(key), (unsigned char*)msg, strlen(msg), NULL, &len);
    char expected[33];
    for(int i=0; i<16; i++) sprintf(&expected[i*2], "%02x", result[i]);
    expected[32] = '\0';
    if(strncmp(argv[3], expected, 32) == 0) return 0;
    return 1;
}
EOF
    gcc -O3 /app/validator.c -o /app/legacy_token_validator -lssl -lcrypto
    strip /app/legacy_token_validator
    rm /app/validator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
