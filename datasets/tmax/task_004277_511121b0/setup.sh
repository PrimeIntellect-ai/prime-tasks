#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc libcurl4-openssl-dev curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

uint32_t crc32(const char *s) {
    uint32_t crc = 0xFFFFFFFF;
    while (*s) {
        crc ^= *s++;
        for (int i = 0; i < 8; i++)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
    }
    return ~crc;
}

int cmp_char(const void *a, const void *b) {
    return (*(const char *)a - *(const char *)b);
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    char *v = argv[1];
    char *payload = argv[2];

    uint32_t crc = crc32(payload);

    int len = strlen(payload);
    char *rot13 = malloc(len + 1);
    for (int i = 0; i < len; i++) {
        char c = payload[i];
        if (c >= 'a' && c <= 'z') rot13[i] = ((c - 'a' + 13) % 26) + 'a';
        else if (c >= 'A' && c <= 'Z') rot13[i] = ((c - 'A' + 13) % 26) + 'A';
        else rot13[i] = c;
    }
    rot13[len] = '\0';

    char *hex = malloc(len * 2 + 1);
    for (int i = 0; i < len; i++) {
        sprintf(hex + (i * 2), "%02x", (unsigned char)rot13[i]);
    }

    qsort(hex, len * 2, 1, cmp_char);

    printf("LEGACY_%s_%08x_%s\n", v, crc, hex);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/legacy_oracle
    strip /app/legacy_oracle

    cat << 'EOF' > /app/integration_tester.c
#include <stdio.h>
int main() {
    printf("Integration test stub.\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
