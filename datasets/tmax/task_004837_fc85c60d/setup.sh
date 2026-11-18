#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    const char *hex_ct = argv[1];
    const char *key = argv[2];
    int key_len = strlen(key);
    if (key_len == 0) return 1;

    int ct_len = strlen(hex_ct) / 2;
    unsigned char *ct = malloc(ct_len);
    for (int i = 0; i < ct_len; i++) {
        sscanf(hex_ct + 2*i, "%2hhx", &ct[i]);
    }

    unsigned char *pt = malloc(ct_len + 1);
    for (int i = 0; i < ct_len; i++) {
        unsigned char b = ct[i];
        unsigned char dec_b = ((b - (i % 256)) & 0xFF) ^ key[i % key_len];
        pt[i] = dec_b;
    }
    pt[ct_len] = '\0';
    printf("%s\n", pt);
    free(ct);
    free(pt);
    return 0;
}
EOF

    gcc -O2 /tmp/legacy.c -o /app/legacy_auditor
    strip /app/legacy_auditor
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
