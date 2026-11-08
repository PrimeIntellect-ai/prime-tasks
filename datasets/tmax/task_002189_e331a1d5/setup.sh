#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl binutils gdb
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/packer.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int c;
    while ((c = fgetc(stdin)) != EOF) {
        int n = c;
        if (n == 0) n = 1;
        unsigned char *buf = malloc(n);
        if (!buf) return 1;
        int read_bytes = 0;
        for (int i = 0; i < n; i++) {
            int b = fgetc(stdin);
            if (b == EOF) break;
            buf[i] = (unsigned char)(b ^ 0x5A);
            read_bytes++;
        }
        for (int i = read_bytes - 1; i >= 0; i--) {
            fputc(buf[i], stdout);
        }
        free(buf);
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/legacy_packer /tmp/packer.c
    upx /app/legacy_packer || true
    rm /tmp/packer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
