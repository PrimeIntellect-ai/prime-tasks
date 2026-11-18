#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy_audit.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("USAGE: legacy_audit <config_string>\n");
        return 1;
    }

    const char *input = argv[1];
    size_t len = strlen(input);
    if (len > 1024) {
        len = 1024; // truncate
    }

    uint8_t state[16] = {
        'D','e','v','S','e','c','O','p','s','P','o','l','i','c','y','!'
    };

    for (size_t i = 0; i < len; i++) {
        state[i % 16] = (state[i % 16] + input[i]) ^ (i & 0xFF);
    }

    for (int i = 0; i < 16; i++) {
        printf("%02x", state[i]);
    }

    if (strstr(input, "CSP:") != NULL) {
        printf(" HAS_CSP");
    }
    if (strstr(input, "Secure") != NULL) {
        printf(" HAS_SECURE");
    }
    if (strstr(input, "Port: 80") != NULL) {
        printf(" HTTP_PORT");
    }
    if (strstr(input, "0600") != NULL) {
        printf(" RESTRICTED_PERMS");
    }

    printf("\n");
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_audit.c -o /app/legacy_audit
    strip /app/legacy_audit
    rm /tmp/legacy_audit.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
