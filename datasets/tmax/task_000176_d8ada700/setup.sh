#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/auth_validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *token = argv[1];
    char username[256];
    int priv_level;
    int sig;
    if (sscanf(token, "%255[^.].%d.%d", username, &priv_level, &sig) != 3) return 1;

    int sum = 0;
    for (int i = 0; username[i] != '\0'; i++) {
        sum += username[i];
    }

    int expected_sig = sum ^ 0x5A;
    if (priv_level == 0 && sig == expected_sig) {
        return 0;
    }
    return 1;
}
EOF

    gcc -o /app/auth_validator /app/auth_validator.c
    strip /app/auth_validator

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/audit_logs.txt
alice.1.111
bob.1.113
charlie.1.109
dave.1.106
eve.1.119
EOF

    chmod 444 /home/user/audit_logs.txt
    chmod -R 777 /home/user
