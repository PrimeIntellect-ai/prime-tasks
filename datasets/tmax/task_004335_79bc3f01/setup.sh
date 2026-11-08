#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace openssl curl
    pip3 install pytest requests

    mkdir -p /app
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    // Hardcoded token
    if (strcmp(argv[1], "TrUSt_N0_1_XyZ99") == 0) {
        return 0;
    }
    return 1;
}
EOF
    gcc -O2 -s -o /app/legacy_validator /tmp/validator.c
    rm /tmp/validator.c
    chmod +x /app/legacy_validator

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
