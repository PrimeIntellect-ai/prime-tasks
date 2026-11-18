#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_checker.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

struct AuthContext {
    char username[64];
    int is_admin;
};

void process_rotation(const char *cert_path) {
    char command[256];
    // Computes the file integrity hash of the new cert
    snprintf(command, sizeof(command), "sha256sum %s > /home/user/rotation_success.log", cert_path);
    system(command);
    printf("Credential rotation successful.\n");
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <username> <cert_path>\n", argv[0]);
        return 1;
    }

    struct AuthContext ctx;
    ctx.is_admin = 0;

    // Vulnerability: Unbounded strcpy into a 64-byte buffer
    strcpy(ctx.username, argv[1]);

    if (strcmp(ctx.username, "admin") == 0) {
        printf("Admin password required (prompt disabled in legacy mode).\n");
        return 1;
    }

    if (ctx.is_admin != 0) {
        process_rotation(argv[2]);
    } else {
        printf("Authentication failed. Access denied.\n");
    }

    return 0;
}
EOF

    gcc -O0 -fno-stack-protector -o /home/user/auth_checker /home/user/auth_checker.c
    chmod +x /home/user/auth_checker

    chmod -R 777 /home/user
