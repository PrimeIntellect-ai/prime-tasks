#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/pentest
    cd /home/user/pentest

    cat << 'EOF' > token_gen.c
#include <stdio.h>

// Generates an authentication token based on a 4-digit PIN and username
unsigned int generate_token(int pin, const char* user) {
    unsigned int hash = pin;
    while (*user) {
        hash = (hash * 33) ^ *user;
        user++;
    }
    return hash;
}
EOF

    cat << 'EOF' > gen_setup.c
#include <stdio.h>

unsigned int generate_token(int pin, const char* user) {
    unsigned int hash = pin;
    while (*user) {
        hash = (hash * 33) ^ *user;
        user++;
    }
    return hash;
}

int main() {
    FILE *f = fopen("captured_token.txt", "w");
    if (f) {
        fprintf(f, "0x%08x\n", generate_token(4281, "admin"));
        fclose(f);
    }
    return 0;
}
EOF

    gcc gen_setup.c -o gen_setup
    ./gen_setup
    rm gen_setup.c gen_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
