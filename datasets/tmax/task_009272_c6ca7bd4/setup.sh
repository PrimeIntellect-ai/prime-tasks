#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential binutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/token_check.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// The secret key embedded in the binary
const char *SECRET_KEY = "Sup3rS3cr3tM4st3rK3y";

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <username> <token>\n", argv[0]);
        return 1;
    }

    char *username = argv[1];
    int provided_token = atoi(argv[2]);

    int checksum = 0;
    for (int i = 0; i < strlen(username); i++) {
        checksum += username[i];
    }
    for (int i = 0; i < strlen(SECRET_KEY); i++) {
        checksum += SECRET_KEY[i];
    }
    checksum = checksum % 256;

    if (provided_token == checksum) {
        printf("Access Granted for %s\n", username);
        return 0;
    } else {
        printf("Access Denied\n");
        return 1;
    }
}
EOF

    gcc /home/user/token_check.c -o /home/user/token_check
    rm /home/user/token_check.c
    chmod +x /home/user/token_check

    useradd -m -s /bin/bash user || true
    chown user:user /home/user/token_check
    chmod -R 777 /home/user
