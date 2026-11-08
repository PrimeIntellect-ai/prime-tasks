#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest requests pycryptodome

    mkdir -p /app
    cat << 'EOF' > /tmp/implant.c
#include <stdio.h>
#include <string.h>

void do_auth(const char* token) {
    if(strcmp(token, "OpDagger_2024") == 0) {
        printf("Auth OK\n");
    }
}

void do_crypto() {
    const char* key = "deadbeefcafebabe";
    printf("Using key %s\n", key);
}

int main() {
    do_auth("test");
    do_crypto();
    return 0;
}
EOF
    gcc -O2 -s /tmp/implant.c -o /app/implant_c2
    rm /tmp/implant.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
