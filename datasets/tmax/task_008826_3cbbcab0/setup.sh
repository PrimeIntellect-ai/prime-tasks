#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/rotate.c
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <secret_key>\n", argv[0]);
        return 1;
    }
    // Vulnerable: secret is exposed in process list
    printf("Rotating credentials using secret: %s\n", argv[1]);

    // Simulate rotation
    FILE *f = fopen("/home/user/rotate.log", "w");
    if (f) {
        fprintf(f, "Credential rotated securely\n");
        fclose(f);
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
