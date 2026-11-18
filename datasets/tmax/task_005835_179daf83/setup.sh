#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.log
[INFO] User admin logged in.
[DEBUG] Token validation failed. Salt used was wX9kP2mR4vLz
[INFO] User test failed login.
[DEBUG] Initialization complete. Loaded salt: wX9kP2mR4vLz
EOF

    cat << 'EOF' > /home/user/legacy_auth.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s username:token\n", argv[0]);
        return 1;
    }

    char *input = argv[1];
    char *colon = strchr(input, ':');
    if (!colon) {
        printf("Invalid format.\n");
        return 1;
    }

    *colon = '\0';
    char *username = input;
    char *token = colon + 1;
    char *salt = "wX9kP2mR4vLz";
    int salt_len = strlen(salt);

    char expected_token[256] = {0};
    for (int i = 0; i < strlen(username); i++) {
        sprintf(expected_token + (i * 2), "%02x", (unsigned char)(username[i] ^ salt[i % salt_len]));
    }

    if (strcmp(token, expected_token) == 0) {
        printf("ACCESS GRANTED. FLAG: DEVSEC_POLICY_ENFORCED_99\n");
        return 0;
    } else {
        printf("ACCESS DENIED.\n");
        return 1;
    }
}
EOF

    gcc /home/user/legacy_auth.c -o /home/user/legacy_auth
    rm /home/user/legacy_auth.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
