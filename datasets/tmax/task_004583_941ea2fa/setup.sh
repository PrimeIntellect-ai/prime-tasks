#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libssl-dev openssl
    pip3 install pytest

    mkdir -p /app/certs
    cd /app/certs
    openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3650 -subj "/CN=Test-CA"
    openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=localhost"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    char* token = argv[1];
    if (strlen(token) != 16) return 1;
    unsigned char bytes[8];
    for(int i=0; i<8; i++) {
        if (sscanf(token + 2*i, "%2hhx", &bytes[i]) != 1) return 1;
    }
    if (bytes[0] != 0xAA) return 1;
    unsigned char x = 0;
    for(int i=0; i<8; i++) x ^= bytes[i];
    if (x == 0x42) return 0;
    return 1;
}
EOF
    gcc -O2 /tmp/validator.c -o /app/token_validator
    strip /app/token_validator
    rm /tmp/validator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
