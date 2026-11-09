#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_server.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        FILE *f = fopen("/home/user/auth_result.txt", "w");
        if(f) { fprintf(f, "AUTH_FAILURE\n"); fclose(f); }
        return 1;
    }

    char *token = argv[1];
    FILE *f = fopen("/home/user/auth_result.txt", "w");
    if (!f) return 1;

    if (strcmp(token, "SuperSecretAppToken2024") == 0) {
        fprintf(f, "AUTH_SUCCESS\n");
    } else {
        fprintf(f, "AUTH_FAILURE\n");
    }
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
