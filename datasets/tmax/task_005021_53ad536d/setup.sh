#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/auth_parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char token[256];
    if (fgets(token, sizeof(token), stdin) == NULL) return 1;

    // Remove newline if present
    token[strcspn(token, "\n")] = 0;

    char *alg = strtok(token, ":");
    char *user = strtok(NULL, ":");
    char *role = strtok(NULL, ":");
    char *sig = strtok(NULL, ":");

    if (!alg || !user || !role) {
        printf("Invalid token format.\n");
        return 1;
    }

    // Vulnerability: alg=none bypasses signature check
    if (strcasecmp(alg, "none") != 0) {
        if (!sig || strcmp(sig, "VALID_SIG") != 0) {
            printf("Signature verification failed.\n");
            return 1;
        }
    }

    if (strcmp(role, "admin") == 0) {
        // Vulnerability: no XSS sanitization on user
        printf("AUDIT_LOG: Access Granted to admin user %s\n", user);
    } else {
        printf("AUDIT_LOG: Access Granted to user %s\n", user);
    }

    return 0;
}
EOF

    gcc -o /home/user/auth_parser /home/user/auth_parser.c
    chmod +x /home/user/auth_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
