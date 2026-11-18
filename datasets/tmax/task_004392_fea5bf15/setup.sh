#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <ctype.h>

int main() {
    int c;
    char hex_pair[3] = {0};
    int hex_idx = 0;

    while ((c = getchar()) != EOF) {
        if (isxdigit(c)) {
            hex_pair[hex_idx++] = (char)c;
            if (hex_idx == 2) {
                int val;
                sscanf(hex_pair, "%2x", &val);
                if (val >= 32 && val <= 126) {
                    putchar(val);
                } else {
                    putchar('.');
                }
                hex_idx = 0;
            }
        }
    }
    putchar('\n');
    return 0;
}
EOF

    gcc -O2 /tmp/legacy.c -o /app/legacy_cleaner
    strip /app/legacy_cleaner
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
