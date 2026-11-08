#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_checker.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/sha.h>

// Security Auditor Note: Token is SHA256(username + salt)
#define AUTH_SALT "SuperS3cr3tS@lt99"

void generate_token(const char* username, char* output_hash) {
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%s%s", username, AUTH_SALT);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)buffer, strlen(buffer), hash);

    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        sprintf(output_hash + (i * 2), "%02x", hash[i]);
    }
    output_hash[64] = '\0';
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <username> <token>\n", argv[0]);
        return 1;
    }

    char expected_token[65];
    generate_token(argv[1], expected_token);

    if (strcmp(argv[2], expected_token) == 0) {
        printf("Access Granted to %s.\n", argv[1]);
        return 0;
    } else {
        printf("Access Denied.\n");
        return 1;
    }
}
EOF

    chmod -R 777 /home/user
