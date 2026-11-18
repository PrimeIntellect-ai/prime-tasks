#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc g++ strace ltrace gdb binutils upx-ucl
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    size_t cap = 1024;
    size_t len = 0;
    unsigned char *buf = malloc(cap);
    if (!buf) return 1;
    int c;
    while ((c = getchar()) != EOF) {
        if (len + 1 >= cap) {
            cap *= 2;
            buf = realloc(buf, cap);
            if (!buf) return 1;
        }
        buf[len++] = c;
    }
    buf[len] = '\0';

    for (size_t i = 0; i + 5 < len; i++) {
        if (memcmp(buf + i, "TOKEN=", 6) == 0) {
            for (size_t j = 0; j < 8 && i + 6 + j < len; j++) {
                buf[i + 6 + j] = '*';
            }
        }
    }

    printf("EVASION_V1|");
    for (size_t i = 0; i < len; i++) {
        if (buf[i] == '<') {
            printf("266c743b");
        } else if (buf[i] == '>') {
            printf("2667743b");
        } else {
            printf("%02x", buf[i]);
        }
    }

    free(buf);
    return 0;
}
EOF

gcc -O2 /tmp/oracle.c -o /app/obfuscator_oracle
strip /app/obfuscator_oracle
upx /app/obfuscator_oracle || true

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
