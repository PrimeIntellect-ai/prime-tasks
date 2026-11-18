#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for compiling the binary and the agent's C++ server
    apt-get install -y g++ gcc curl

    # Create the app directory and the legacy_crypto binary
    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_crypto.c
#include <stdio.h>
#include <string.h>
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char* pw = argv[1];
    for (int i = 0; i < strlen(pw); i++) {
        unsigned char c = (pw[i] ^ 0x37) + 3;
        printf("%02x", c);
    }
    printf("\n");
    return 0;
}
EOF
    gcc -O2 -s /tmp/legacy_crypto.c -o /app/legacy_crypto
    rm /tmp/legacy_crypto.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
